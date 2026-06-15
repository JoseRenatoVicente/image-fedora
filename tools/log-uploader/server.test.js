'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const os = require('node:os');
const path = require('node:path');

async function withServer(fn) {
  const uploadDir = await fs.mkdtemp(path.join(os.tmpdir(), 'log-uploader-test-'));
  process.env.UPLOAD_DIR = uploadDir;
  delete require.cache[require.resolve('./server.js')];
  const { createApp } = require('./server.js');
  const server = createApp();
  await new Promise((resolve) => server.listen(0, '127.0.0.1', resolve));
  const { port } = server.address();
  try {
    await fn(`http://127.0.0.1:${port}`, uploadDir);
  } finally {
    await new Promise((resolve) => server.close(resolve));
    await fs.rm(uploadDir, { recursive: true, force: true });
    delete process.env.UPLOAD_DIR;
  }
}

test('serves index page with collector command', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/`);
    const body = await response.text();
    assert.equal(response.status, 200);
    assert.match(body, /VM Log Uploader/);
    assert.match(body, /collect-vm-logs\.sh/);
  });
});

test('serves collector script', async () => {
  await withServer(async (baseUrl) => {
    const response = await fetch(`${baseUrl}/collect-vm-logs.sh`);
    const body = await response.text();
    assert.equal(response.status, 200);
    assert.match(response.headers.get('content-type'), /text\/x-shellscript/);
    assert.match(body, /journalctl -b/);
    assert.match(body, /plasma-org\.kde\.plasma\.desktop-appletsrc/);
  });
});

test('receives binary upload and exposes it for download', async () => {
  await withServer(async (baseUrl, uploadDir) => {
    const payload = Buffer.from('fake tarball bytes');
    const upload = await fetch(`${baseUrl}/upload?name=sample.tar.gz`, {
      method: 'POST',
      headers: { 'content-type': 'application/gzip' },
      body: payload,
    });
    assert.equal(upload.status, 201);

    const saved = await fs.readFile(path.join(uploadDir, 'sample.tar.gz'));
    assert.deepEqual(saved, payload);

    const download = await fetch(`${baseUrl}/uploads/sample.tar.gz`);
    assert.equal(download.status, 200);
    assert.equal(await download.text(), 'fake tarball bytes');
  });
});

test('sanitizes upload filenames', async () => {
  await withServer(async (baseUrl, uploadDir) => {
    const upload = await fetch(`${baseUrl}/upload?name=../../bad name.tar.gz`, {
      method: 'POST',
      body: 'content',
    });
    assert.equal(upload.status, 201);
    const files = await fs.readdir(uploadDir);
    assert.deepEqual(files, ['bad_name.tar.gz']);
  });
});
