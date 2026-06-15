# VM Log Uploader

Servidor local para coletar logs da VM Fedora/KDE e receber o arquivo gerado.

## Subir no host

```bash
node tools/log-uploader/server.js
```

Por padrão o servidor escuta em `0.0.0.0:3000` e salva uploads em `tools/log-uploader/uploads/`.

Para mudar a porta:

```bash
PORT=3333 node tools/log-uploader/server.js
```

## Rodar na VM

Descubra o IP do host acessível pela VM. Em QEMU user networking normalmente funciona:

```bash
HOST_URL=http://10.0.2.2:3000
```

Se estiver usando bridge ou outra rede, use o IP do host na rede da VM.

Baixe e execute:

```bash
curl -fsSL "$HOST_URL/collect-vm-logs.sh" -o /tmp/collect-vm-logs.sh
bash /tmp/collect-vm-logs.sh "$HOST_URL/upload"
```

Depois abra no host:

```text
http://localhost:3000/
```

## O que o script coleta

- `journalctl -b` e `journalctl --user -b`
- `plasma-org.kde.plasma.desktop-appletsrc`
- `plasmashellrc`, `kdeglobals`, `plasmarc`, `kscreenlockerrc`
- `/etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc`
- Pacotes KDE/Plasma instalados
- Verificação de applets referenciados sem pacote instalado
- Arquivos Mokka look-and-feel relevantes
