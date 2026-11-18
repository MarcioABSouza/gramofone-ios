# Instalação no iPod touch 7 (iOS 15.8.8)

Dois pré-requisitos: **TrollStore instalado** (uma vez) e o **`.ipa`** mais recente.

## 1. TrollStore (uma vez por aparelho)

O TrollStore instala `.ipa` permanentemente, sem Apple ID, sem revisão, sem expiração. No iOS
15.8.8 ele é instalado pelo **TrollRestore**, que roda em **Linux/macOS/Windows** — sem Mac e sem
iPhone.

### Pré-requisitos

- iPod desbloqueado, com **Find My desligado** (Ajustes → [nome] → Buscar → desativar).
- **App “Dicas” (Tips) instalado** — ele é substituído pelo helper. Se você o apagou, reinstale
  pela App Store.
- Cabo USB e um computador com **Python 3**.
- **Backup**: o TrollRestore usa um backup modificado; faça um backup antes (iCloud ou `idevicebackup2`).

### Pegadinha: versão do `pymobiledevice3`

O TrollRestore (2024) importa `pymobiledevice3.cli.cli_common.Command`, que **não existe mais** nas
versões atuais (o `latest` quebra na importação). Use a **4.9.6** num venv separado:

```bash
mkdir -p ~/Code/tools && cd ~/Code/tools
curl -sSL -o tr.zip https://github.com/JJTech0130/TrollRestore/releases/download/1.0/TrollRestore_Linux.zip
unzip -q tr.zip -d TrollRestore-Linux && cd TrollRestore-Linux

# venv: se `python3 -m venv` falhar com "ensurepip is not available",
# instale python3-venv OU use o uv (sem sudo):
uv venv --python 3.13 .venv
uv pip install --python .venv/bin/python "pymobiledevice3==4.9.6" bpylist2 rich requests click packaging

./.venv/bin/python -c "from pymobiledevice3.cli.cli_common import Command; print('ok')"
```

### Instalação

1. Conecte o iPod, desbloqueie e toque em **Confiar**.
2. Confirme que ele aparece:
   ```bash
   # usbmuxd sobe sozinho ao plugar (serviço estático do pacote)
   python3 -m pymobiledevice3 usbmux list   # ou use o venv: ./.venv/bin/python -m …
   ```
3. Rode o instalador e digite **`Tips`** quando ele pedir o app:
   ```bash
   printf 'Tips\n' | ./.venv/bin/python trollstore.py
   ```
4. Ele cria o backup modificado, restaura e **reinicia o iPod** (sem progresso na tela — não
   desconecte).
5. No iPod: abra **Dicas** → **Install TrollStore** → o aparelho dá respring e o ícone do
   TrollStore aparece.
6. Abra **TrollStore** → **Settings** → **Install Persistence Helper** → **Tips**.

Pronto. O app Dicas original volta se você apagá-lo e reinstalar da App Store.

### Plano B (se o TrollStore não instalar)

- **SideStore** (Apple ID grátis): instala apps assinados e re-assina a cada **7 dias**; precisa de
  um *pairing file* gerado uma vez no computador.
- **Conta de desenvolvedor** (US$ 99/ano) + instalação **ad-hoc** (sem review, validade de 1 ano).

## 2. Instalar o Gramofone

### Opção A — direto no iPod (sem computador)

No **Safari** do iPod:

```
https://github.com/MarcioABSouza/gramofone-ios/releases/download/ios-latest/Gramofone.ipa
```

→ **Baixar** → Arquivos → **Downloads** → abrir o `.ipa` → **Compartilhar → TrollStore**
(ou TrollStore → **+**).

### Opção B — pela LAN (mais rápido)

No computador, com o `.ipa` numa pasta dedicada:

```bash
mkdir -p ~/Code/tools/ipa-share && cd ~/Code/tools/ipa-share
curl -sL -O https://github.com/MarcioABSouza/gramofone-ios/releases/download/ios-latest/Gramofone.ipa

# setsid é importante: sem ele o servidor morre junto com o terminal
setsid nohup python3 -m http.server 8099 --bind 0.0.0.0 > /tmp/http-ipa.log 2>&1 < /dev/null &

curl -sI http://<ip-do-pc>:8099/Gramofone.ipa   # espera 200
```

No iPod: `http://<ip-do-pc>:8099/Gramofone.ipa` → TrollStore → **+**.
Encerre depois: `fuser -k 8099/tcp`.

### Atualizar para uma versão nova

Instale o `.ipa` **por cima** (mesmo bundle id). Sessão, downloads e fila são preservados.

## 3. Primeiro uso

1. Abra o app → tela de login com o campo do servidor preenchido
   (`http://192.168.0.100:8998` por padrão).
2. **Testar servidor** deve responder `gramofone-api respondeu ok`.
3. Entre com um usuário do Gramofone (o primeiro usuário é `manager`).
4. A sessão fica no Keychain (refresh de 365 dias) — depois disso, o app abre direto.

> A stack é **HTTP na LAN**: o `Info.plist` libera cleartext (`NSAllowsArbitraryLoads`). Se um dia
> houver TLS, troque por `NSExceptionDomains` do host e mude `COOKIE_SECURE` no backend.

## 4. Problemas comuns no aparelho

| Sintoma | Causa / solução |
|---|---|
| App instalado mas sem ícone | cache do SpringBoard → TrollStore → **Refresh Icon Cache** (ou reiniciar) |
| Ícone com borda preta | versão antiga (0.4.x) gerada com fundo do tema; atualizar para 0.5.1+ |
| “Sem conexão com o servidor” no login | iPod em outra rede, servidor desligado, ou `:8998` bloqueado |
| Login responde 429 | trava de força bruta do backend (3 falhas/15 min) |
| Abre em “Baixados” e não na biblioteca | sem rede: comportamento esperado (sessão offline) |
| Scrobble não aparece no Last.fm | confira **Conta → Na fila** e use **Enviar scrobbles agora** |
