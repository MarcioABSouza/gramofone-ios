# Histórico de versões

Datas em 2026. Todas as versões foram publicadas como `.ipa` sem assinatura em
`releases/tag/ios-latest` e instaladas via TrollStore no iPod touch 7 (iOS 15.8.8).

## 0.6.0 — build 8

- **Favoritar a música atual** no player em tela cheia (coração; reflete o estado do servidor).
- **Adicionar a música atual a uma playlist existente** (sheet com as playlists do usuário). Se a
  música já estiver na playlist, o servidor responde 409 e a sheet avisa, sem dizer que foi adicionada.
- **Favoritas** aparece na aba Listas (somente leitura).
- Favorito e playlist ficam desabilitados sem rede; tocar baixados continua funcionando.
- **Downloads cancelados não voltam**: remover um álbum durante o download não grava mais o manifesto.
- **Sessão**: renovações concorrentes compartilham uma só chamada (o refresh é rotativo; duas
  chamadas com o mesmo token faziam o servidor revogar todas as sessões). Sessão só encerra com
  401 do refresh — falha de rede mantém o usuário logado.
- **Manifesto tolerante**: uma faixa malformada não derruba o álbum; pastas com manifesto ilegível
  aparecem como aviso na Conta, sem apagar nada.
- Instalação por cima da 0.5.1 preserva os downloads (mesmo bundle ID; formato do manifesto só ganhou
  leitura tolerante).

## 0.5.1 — build 7 (18/11/2026)

Correções reportadas no aparelho:

- **Listas** voltaram a carregar — `GET /lists` devolve `{data:[…]}` e o cliente desembrulha.
- **Player em tela cheia**: controles refeitos para caber em 320 pt (antes 360 pt empurravam o
  chevron e o botão de repeat para fora da tela).
- **Ícone do app**: o PNG do logo tem fundo transparente; a geração agora achata em `#dc2626`
  (vermelho do logo) em vez do preto do tema → ícone vermelho de ponta a ponta, sem alpha.
- **Sessão offline**: perfil em cache (`UserDefaults`); falha de rede não manda mais para o login.
  Aba **Baixados** vira a padrão sem rede; `revalidate()` valida o token quando a conexão volta.
- **Scrobble offline**: flush após restore/login, timer de 60 s enquanto online e botão
  **“Enviar scrobbles agora”** em Conta.

## 0.5.0 — build 6 (18/11/2026)

- **Listas**: tela única com segmentado **Álbuns | Músicas**; **Tocar** e **Aleatório** (embaralha
  as **faixas**, não a ordem dos álbuns); lista de músicas toca a partir da linha escolhida.
- **Ordenação da Biblioteca**: título, artista, ano e adicionado, com direção, persistida.
- **Aba Baixados**: grade offline, “N álbuns · X MB”, **Tocar tudo** e **Aleatório**.
- **Adicionar à fila** no detalhe do álbum (sem duplicar; fila vazia começa a tocar).
- Detalhe de álbum **funciona sem rede** quando baixado (monta do `manifest.json`).
- Build passou a usar `macos-15-intel` (o pool arm64 estava sem capacidade).

## 0.4.0 — build 5 (18/11/2026)

- **Player**: fila, áudio em segundo plano, tela de bloqueio (play/pause/next/prev/seek), repeat
  `off→one→all`, retomada após interrupção, snapshot da fila.
- **Offline**: download por álbum com progresso; player toca do disco; remover download.
- **Scrobble**: fila local (`Documents/scrobble-queue.json`), regra >30 s e metade/4 min,
  idempotência por `playId`, envio em ordem removendo só após 2xx.
- **Acabamento**: mini player com progresso, player em tela cheia com slider e fila, aviso de
  “sem conexão”, contagem de pendências e espaço usado na aba Conta.

## 0.3.1 — build 4 (18/11/2026)

- **Correção**: `duration` das faixas vem **fracionário** (`252.384`); o modelo passou a `Double`.
  Antes a tela de álbum falhava com “não entendi a resposta do servidor”.
- Mensagens de decodificação passaram a indicar o campo (`campo ausente: …`, `tipo inesperado em …`).

## 0.3.0 — build 3 (18/11/2026)

- **Biblioteca**: grade, busca com debounce, paginação de 24.
- **Detalhe do álbum**: capa, metadados e faixas com número/duração; faixa sem cópia local
  desabilitada com `icloud.slash`.
- Conta e logout movidos para uma folha acessada pelo botão de perfil.

## 0.2.0 — build 2 (18/11/2026)

- **Login** com sessão persistida no Keychain, refresh rotativo e retry único em 401.
- Home provisória com dados da sessão (usuário, papel, servidor, Last.fm).

## 0.1.0 — build 1 (18/11/2026)

- Prova da cadeia **CI → `.ipa` → TrollStore → rede**: app de uma tela que testa `GET /api/health`.
- Ícone reaproveitado do frontend; `Info.plist` com cleartext liberado e `UIBackgroundModes: audio`.
