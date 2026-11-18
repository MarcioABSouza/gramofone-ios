# Gramofone iOS — plano

Cliente **Gramofone** para iPod touch 7 (A10, **iOS 15.8.8**): toca a biblioteca do servidor na
LAN, baixa álbuns para ouvir offline e enfileira os scrobbles para o Last.fm subirem depois.

## Restrição dura

**Não depender de Mac físico nem de iPhone físico.** Como isso é satisfeito:

| Etapa | Como | Depende de hardware Apple? |
|---|---|---|
| Compilar | **CI macOS** (GitHub Actions `macos-14/15`) | não — é alugado por minutos |
| Empacotar | `xcodebuild` Release + `Payload/` → `.ipa` sem assinatura | não |
| Instalar | **TrollStore** (instalado via **TrollRestore**, que roda no Linux) | não |
| Rodar | app permaassinado, sem Apple ID, sem expiração | não |

Não existe contorno para o compilador: Swift só compila em macOS. O CI é a única dependência
irredutível — e é gratuita em repositório público (este repo existe por isso: cliente puro, sem
backend e sem segredos).

## Decisões

| Tema | Decisão |
|---|---|
| Base de código | **SwiftUI enxuto**, não o port do `gramofone-bare` (RN) |
| Escopo | player + biblioteca + download/offline + scrobble. Sem cifras, notas, listas, tags |
| Sessão | `Authorization: Bearer` + `refreshToken` no body (365 dias), tokens no Keychain |
| Offline | `Documents/albums/<albumId>/` + `manifest.json` (mesmo padrão do Android) |
| Scrobble | fila em `Documents/scrobble-queue.json`, flush no launch/foreground/rede |
| Instalação | TrollStore; SideStore é plano B (7 dias) |
| Backend | **zero mudança** — só endpoints existentes |

## Não-objetivos (por enquanto)

- iPad, múltiplos servidores, tema claro, iCloud, widgets, CarPlay.
- Paridade com o app Android (listas, favoritos, avaliações, cifras, anotações).
- Publicação na App Store (não é possível com essa toolchain, e não é o objetivo).

## Arquitetura

```
gramofone-ios/
├── project.yml                     # XcodeGen (fonte da verdade do projeto Xcode)
├── .github/workflows/ios.yml       # build + artefato .ipa
├── Gramofone/
│   ├── App/          GramofoneApp.swift, RootView.swift, Info.plist
│   ├── Core/         APIClient, Session, Keychain, Settings, Reachability, URL+Media
│   ├── Models/       Album, AlbumDetail, Track, Auth
│   ├── Player/       PlaybackController, Queue, NowPlaying
│   ├── Offline/      DownloadManager, OfflineStore
│   ├── Scrobble/     ScrobbleQueue, ScrobbleRules
│   └── UI/           LoginView, LibraryView, AlbumView, PlayerView, SettingsView
└── README.md
```

Camadas: `UI` → `Core/Player/Offline/Scrobble` → `APIClient`. Nada de dependência externa (sem
SwiftPM remoto) para o build no CI ser reprodutível e rápido.

### Telas (MVP)

1. **Login** — URL do servidor (default `http://192.168.0.100:8998`), e-mail, senha; guarda em Keychain.
2. **Biblioteca** — grade de álbuns (`GET /albums?local=true`), busca (`search`), paginação.
3. **Álbum** — capa, faixas, **Tocar** e **Baixar para offline** (progresso por álbum).
4. **Player** — tela cheia com capa, transporte, fila. Estado também na barra inferior.
5. **Ajustes** — servidor, scrobble on/off, uso de disco offline (baixados + remover), logout.

### Player

- Um único `AVPlayer` (`AVAudioSession` categoria `.playback`, `UIBackgroundModes: audio`).
- Fila própria (array + índice) persistida em `Documents/queue.json` para retomar no launch.
- `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` (play/pause/next/prev/seek).
- Origem da faixa: arquivo local, se baixada; senão `GET /api/media/<filePath>` (suporta Range/seek).
- Ao iniciar a faixa: `POST /plays` + `now-playing` (best-effort, nunca bloqueia o áudio).
- Regras de scrobble iguais às do web: duração > 30 s e metade da faixa **ou** 4 min de tempo
  realmente tocado; `playId` novo por ouvida; repeat-one reinicia a ouvida.

### Offline

- `DownloadManager` baixa faixa a faixa (`URLSession` com progresso), grava em
  `Documents/albums/<albumId>/`, mais `cover.jpg` e `manifest.json`
  (`{ albumId, title, artist, year, tracks: [{ songId, trackId, title, artist, duration, fileName }] }`).
- `OfflineStore` lista o que está baixado e valida o arquivo no disco antes de tocar.
- Sem background download no MVP (a tela precisa ficar aberta); `URLSession` background fica para o
  fim (fase 6).

### Scrobble (fila local)

- `ScrobbleQueue` grava JSON append-only em `Documents/scrobble-queue.json`:
  `{ title, artist, album, duration, playId, startedAt }` — exatamente o payload do endpoint.
- `playId` gerado no cliente (UUID) garante idempotência no backend.
- Flush: ao abrir o app, ao voltar do background e quando `NWPathMonitor` detectar rede. Cada item
  é removido **só** após resposta 2xx; 401 renova a sessão e tenta de novo; 429/5xx mantém na fila.

## Contrato da API usado (já existe, nada a criar)

| Uso | Chamada |
|---|---|
| Health (fase 1) | `GET /health` |
| Login | `POST /auth` `{ email, password }` → `{ token, refreshToken, user }` |
| Renovar | `POST /auth/refresh` `{ refreshToken }` → `{ token, refreshToken }` |
| Sessão | `GET /auth/me` |
| Biblioteca | `GET /albums?local=true&skip=0&take=24&search=&sort=title&order=asc` → `{ data, total, localTotal }` |
| Álbum | `GET /albums/:id` → `{ album, localAlbumId, trackSource, tracks[], songs[], userStatus }` |
| Capa | `GET /api/covers/:albumId` |
| Áudio | `GET /api/media/<filePath>` (Range/seek; `filePath` vem em `tracks[]`) |
| Histórico | `POST /plays` `{ trackId?, songId?, albumId?, title, artist?, albumTitle?, duration? }` |
| Scrobble | `POST /lastfm/scrobble` `{ title, artist?, album?, duration, playId, startedAt }` |
| Tocando agora | `POST /lastfm/scrobble/now-playing` `{ title, artist?, album?, duration }` |
| Scrobble ligado? | `GET /lastfm/scrobble/status` |

Observações confirmadas no backend:

- `tracks[]` traz `id, number, title, artist, duration, filePath, songId` (quando `trackSource=local`;
  em `catalog`, `filePath` é `null` e a faixa não toca — a UI desabilita).
- `duration` é **segundos** (inteiro) nos endpoints de scrobble.
- O backend aceita scrobble de até **14 dias** atrás → fila offline não precisa de ajuste.
- O backend **não** tem deduplicação por `playId` em `/plays` (só no scrobble).

## Compatibilidade iOS 15 (armadilhas)

- `NavigationStack`/`NavigationSplitView`, `ScrollView` com `.scrollTargetBehavior`, `Grid` novo,
  `ContentUnavailableView`, `Observation` (`@Observable`) e `SwiftData` **não existem no 15**.
  Usar `NavigationView`, `@ObservedObject`/`ObservableObject`, `LazyVGrid`, `@StateObject`.
- `AVPlayer` + `AVAudioSession` ok; `AVAudioApplication` (iOS 17) não.
- ATS: `Info.plist` com `NSAllowsArbitraryLoads = true` (app privado, sem review) para falar HTTP na LAN.
- Sem `BGTaskScheduler` no MVP (não é necessário para tocar com tela apagada).

## Toolchain e CI

`project.yml` (XcodeGen) é a fonte da verdade — o `.xcodeproj` é gerado no CI, não versionado.

```yaml
name: Gramofone
options:
  bundleIdPrefix: dev.marciosouza
  deploymentTarget: { iOS: "15.0" }
targets:
  Gramofone:
    type: application
    platform: iOS
    sources: [Gramofone]
    info:
      path: Gramofone/App/Info.plist
      properties:
        UIBackgroundModes: [audio]
        NSAppTransportSecurity: { NSAllowsArbitraryLoads: true }
```

Workflow (`macos-14`), sem assinatura:

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project Gramofone.xcodeproj -scheme Gramofone -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir Payload && cp -R build/Release-iphoneos/Gramofone.app Payload/
zip -r Gramofone.ipa Payload
```

O `.ipa` sai como **artifact** do run (30 dias de retenção). Download no Linux, sem Mac.

## Instalação no iPod (uma vez)

**TrollStore via TrollRestore** (roda no Linux, iOS 15.8.8 está na faixa 15.8.7–15.8.8):

1. Backup do iPod (ou assumir que o restore pode apagar dados), desligar **Find My**.
2. Baixar `TrollRestore_Linux.zip` do repo oficial (`JJTech0130/TrollRestore`).
3. `pip3 install -r requirements.txt && python3 trollstore.py` → digitar `Tips`.
4. O aparelho reinicia; abrir **Dicas** → *Install TrollStore* → respring.
5. TrollStore → Ajustes → *Install Persistence Helper* → **Dicas**.
6. Baixar o `.ipa` no aparelho (Files/servidor HTTP local) → TrollStore → *Install IPA*.

Riscos e reversão: o TrollRestore substitui o binário do app Dicas (recupera-se reinstalando da App
Store) e usa backup modificado (Find My reativável depois). Se o TrollStore falhar, plano B:
**SideStore** com Apple ID grátis (re-assina a cada 7 dias, pairing file gerado no Linux).

## Fases (com checkpoint no aparelho)

| Fase | Entrega | Aceite |
|---|---|---|
| **0** | Repo + workflow + app "hello" que chama `GET /health` | CI gera `.ipa`; TrollStore instala; app abre e fala com o servidor (ATS ok) |
| **1** | Login + sessão persistida | fechar/abrir o app mantém logado; refresh funciona |
| **2** | Biblioteca + álbum | lista paginada, busca, detalhe com faixas |
| **3** | Player + tela de bloqueio | toca com tela apagada; controles no lock screen; seek |
| **4** | Download + offline | desligar Wi-Fi: baixado toca do disco; não baixado mostra erro amigável |
| **5** | Scrobble + histórico | ouvir offline → religar Wi-Fi → scrobble no Last.fm com horário original |
| **6** | Acabamento | capa em cache, fila persistente, indicador offline, ícone do app, README |

**Todas as fases 0–6 foram concluídas e validadas no aparelho.** Depois delas entraram duas
extensões pedidas em uso: a fase **7** (listas de álbuns/músicas, ordenação da biblioteca, aba
Baixados com “Tocar tudo” e “Adicionar à fila”) e a **7.1** (correções de envelope de `/lists`,
layout do player em 320 pt, ícone full-bleed, **sessão offline** e flush de scrobble com timer).
O histórico completo está em [docs/CHANGELOG.md](docs/CHANGELOG.md).

A fase 0 é a que valida a premissa inteira (CI → IPA → TrollStore → rede) em ~1 dia.

## Riscos

| Risco | Mitigação |
|---|---|
| TrollRestore no 15.8.8 falha ou deixa o aparelho instável | backup antes; SideStore como plano B; o iPod não tem nada crítico |
| Runner macOS indisponível/limitado | repo público (minutos ilimitados); Codemagic como reserva |
| SwiftUI do iOS 15 tem menos API | já mapeado acima; evitar dependências que exijam 16+ |
| Sem App Store = sem update automático | cada versão é um IPA novo; versionar `CFBundleShortVersionString` |
| Contrato da API mudar | o iOS vira cliente oficial: regra do `AGENTS.md` (só acrescentar campo/rota) passa a valer |
| Download interrompido ao bloquear a tela | MVP exige tela aberta; background `URLSession` na fase 6 |

## Decisões tomadas (as “abertas” do plano original)

1. **Ícone**: reaproveitado de `frontend/public/icons`, gerado em 1024 com fundo **full-bleed
   `#dc2626`** (o PNG original tem alpha; achatar em preto criava uma borda escura).
2. **Bundle**: `dev.marciosouza.gramofone`.
3. **Escopo**: o MVP ficou sem favoritos/avaliações/listas de edição; em uso foram adicionadas
   listas (somente leitura), ordenação e a aba de baixados.

## Referências

- Backend: `~/Code/projects/gramofone` (`AGENTS.md` → contratos; `backend/src/interfaces/http/router.ts`).
- App Android (mesmos endpoints e formato de fila): `~/Code/projects/gramofone-bare`.
- TrollStore: `opa334/TrollStore` · TrollRestore: `JJTech0130/TrollRestore`.
- LineageOS/CI: GitHub Actions `macos-14` (Xcode 15/16).

## Progresso

| Data | Fase | Entrega |
|---|---|---|
| 18/11/2026 | 0 | CI `macos-15` gera `.ipa` sem assinatura; TrollStore instalado via TrollRestore; app chamou `/api/health` no iPod |
| 18/11/2026 | 1 | login + sessão persistida (refresh token no Keychain, rotação + retry em 401) validados no iPod |
| 18/11/2026 | 2 | biblioteca (grade, busca, paginação) + detalhe do álbum — validada no iPod |
| 18/11/2026 | 3–6 | player (fila, background, lock screen), download/offline, fila de scrobble e acabamento — validados no iPod (0.4.0) |
| 18/11/2026 | 7 | listas de álbuns e músicas (tocar/aleatório), ordenação da biblioteca, aba Baixados com “Tocar tudo” e “Adicionar à fila” — 0.5.0 validada |
| 18/11/2026 | 7.1 | correções: `/lists` com envelope `data`, controles do player em 320 pt, ícone full-bleed `#dc2626`, **sessão offline** (abre sem rede com o perfil em cache) e flush de scrobble com timer + botão manual — 0.5.1 validada no iPod |

**Resultado:** cliente instalado e em uso, versão **0.5.1 (build 7)**, publicada em
`releases/tag/ios-latest`. Documentação de operação em [docs/](docs/): build, instalação,
arquitetura, API e histórico.

Notas de campo: `macos-14` foi aposentado em 02/11/2026 (o workflow usa `macos-15`); o
`pymobiledevice3` atual quebrou o `TrollRestore` (API `Command` removida) — a instalação usou a
**4.9.6** num venv separado.
