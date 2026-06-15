#!/usr/bin/env node
'use strict';

const http = require('node:http');
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const { pipeline } = require('node:stream/promises');

const ROOT = __dirname;
const SCRIPT_PATH = path.join(ROOT, 'collect-vm-logs.sh');
const UPLOAD_DIR = process.env.UPLOAD_DIR || path.join(ROOT, 'uploads');
const HOST = process.env.HOST || '0.0.0.0';
const PORT = Number.parseInt(process.env.PORT || '3000', 10);
const MAX_UPLOAD_BYTES = Number.parseInt(process.env.MAX_UPLOAD_BYTES || String(50 * 1024 * 1024), 10);

function safeName(name) {
  const base = path.basename(String(name || 'vm-logs.tar.gz'));
  const cleaned = base.replace(/[^A-Za-z0-9._-]/g, '_');
  return cleaned || 'vm-logs.tar.gz';
}

function htmlEscape(value) {
  return String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function send(res, status, body, type = 'text/plain; charset=utf-8') {
  res.writeHead(status, {
    'content-type': type,
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

async function listUploads() {
  await fsp.mkdir(UPLOAD_DIR, { recursive: true });
  const entries = await fsp.readdir(UPLOAD_DIR, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    if (!entry.isFile()) continue;
    const filePath = path.join(UPLOAD_DIR, entry.name);
    const stat = await fsp.stat(filePath);
    files.push({ name: entry.name, size: stat.size, mtime: stat.mtime });
  }
  files.sort((a, b) => b.mtime - a.mtime);
  return files;
}

async function renderIndex(req) {
  const host = req.headers.host || `localhost:${PORT}`;
  const baseUrl = `http://${host}`;
  const files = await listUploads();
  const uploads = files.length === 0
    ? '<li>Nenhum upload recebido ainda.</li>'
    : files.map((file) => {
      const name = htmlEscape(file.name);
      const sizeKb = (file.size / 1024).toFixed(1);
      return `<li><a href="/uploads/${encodeURIComponent(file.name)}">${name}</a> (${sizeKb} KiB, ${htmlEscape(file.mtime.toISOString())})</li>`;
    }).join('\n');

  return `<!doctype html>
<html lang="pt-BR">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>VM Log Uploader</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 920px; margin: 40px auto; padding: 0 18px; line-height: 1.5; }
    code, pre { background: #f2f2f2; border-radius: 6px; }
    code { padding: 2px 5px; }
    pre { padding: 12px; overflow: auto; }
    a { color: #0b57d0; }
  </style>
</head>
<body>
  <h1>VM Log Uploader</h1>
  <p>Use isto dentro da VM para coletar e enviar os logs:</p>
  <pre>curl -fsSL ${baseUrl}/collect-vm-logs.sh -o /tmp/collect-vm-logs.sh
bash /tmp/collect-vm-logs.sh ${baseUrl}/upload</pre>
  <p>Download direto do script: <a href="/collect-vm-logs.sh">collect-vm-logs.sh</a></p>
  <h2>Uploads recebidos</h2>
  <ul>${uploads}</ul>
</body>
</html>
`;
}

async function serveScript(res) {
  const body = await fsp.readFile(SCRIPT_PATH);
  res.writeHead(200, {
    'content-type': 'text/x-shellscript; charset=utf-8',
    'content-length': body.length,
    'content-disposition': 'attachment; filename="collect-vm-logs.sh"',
  });
  res.end(body);
}

async function serveUpload(url, res) {
  const name = safeName(decodeURIComponent(url.pathname.slice('/uploads/'.length)));
  const filePath = path.join(UPLOAD_DIR, name);
  if (!filePath.startsWith(path.resolve(UPLOAD_DIR) + path.sep)) {
    send(res, 400, 'invalid file name\n');
    return;
  }
  try {
    const stat = await fsp.stat(filePath);
    res.writeHead(200, {
      'content-type': 'application/gzip',
      'content-length': stat.size,
      'content-disposition': `attachment; filename="${name}"`,
    });
    fs.createReadStream(filePath).pipe(res);
  } catch (error) {
    if (error.code === 'ENOENT') send(res, 404, 'not found\n');
    else throw error;
  }
}

async function receiveUpload(req, url, res) {
  const contentLength = Number.parseInt(req.headers['content-length'] || '0', 10);
  if (contentLength > MAX_UPLOAD_BYTES) {
    send(res, 413, `upload too large (max ${MAX_UPLOAD_BYTES} bytes)\n`);
    req.destroy();
    return;
  }

  await fsp.mkdir(UPLOAD_DIR, { recursive: true });
  const requestedName = url.searchParams.get('name') || `vm-logs-${new Date().toISOString().replace(/[:.]/g, '-')}.tar.gz`;
  const fileName = safeName(requestedName.endsWith('.tar.gz') ? requestedName : `${requestedName}.tar.gz`);
  const filePath = path.join(UPLOAD_DIR, fileName);
  const resolvedUploadDir = path.resolve(UPLOAD_DIR);
  const resolvedFilePath = path.resolve(filePath);
  if (!resolvedFilePath.startsWith(resolvedUploadDir + path.sep)) {
    send(res, 400, 'invalid upload name\n');
    return;
  }

  let received = 0;
  req.on('data', (chunk) => {
    received += chunk.length;
    if (received > MAX_UPLOAD_BYTES) req.destroy(new Error('upload too large'));
  });

  try {
    await pipeline(req, fs.createWriteStream(filePath, { flags: 'wx' }));
    send(res, 201, `uploaded ${fileName}\n`);
  } catch (error) {
    if (error.code === 'EEXIST') {
      send(res, 409, `file already exists: ${fileName}\n`);
      return;
    }
    await fsp.rm(filePath, { force: true }).catch(() => {});
    if (error.message === 'upload too large') send(res, 413, `upload too large (max ${MAX_UPLOAD_BYTES} bytes)\n`);
    else throw error;
  }
}

function createApp() {
  return http.createServer(async (req, res) => {
    try {
      const url = new URL(req.url, `http://${req.headers.host || 'localhost'}`);
      if (req.method === 'GET' && url.pathname === '/') {
        send(res, 200, await renderIndex(req), 'text/html; charset=utf-8');
      } else if (req.method === 'GET' && url.pathname === '/collect-vm-logs.sh') {
        await serveScript(res);
      } else if (req.method === 'POST' && url.pathname === '/upload') {
        await receiveUpload(req, url, res);
      } else if (req.method === 'GET' && url.pathname.startsWith('/uploads/')) {
        await serveUpload(url, res);
      } else {
        send(res, 404, 'not found\n');
      }
    } catch (error) {
      console.error(error);
      if (!res.headersSent) send(res, 500, 'internal server error\n');
      else res.destroy(error);
    }
  });
}

if (require.main === module) {
  const server = createApp();
  server.listen(PORT, HOST, () => {
    console.log(`VM Log Uploader listening on http://${HOST}:${PORT}`);
    console.log(`Uploads directory: ${UPLOAD_DIR}`);
  });
}

module.exports = { createApp, safeName, UPLOAD_DIR };
