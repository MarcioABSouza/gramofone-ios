# Arquitetura

App SwiftUI, iOS 15.0+, sem dependência externa (nenhum SwiftPM/CocoaPods). Isso mantém o build no
CI rápido e reprodutível.

```
Gramofone/
├── App/          GramofoneApp (composição), RootView (roteamento por sessão), Info.plist
├── Core/         APIClient, Session, Keychain, Settings, OfflineStore, NetworkMonitor
├── Models/       Auth, Library, Lists
├── Player/       PlayerController, QueueItem, ScrobbleQueue
├── Offline/      DownloadManager, OfflineDetail
└── UI/           Login, Library, Album, Lists, AlbumListPage, SongListPage, Player, MiniPlayer,
                  AddToListSheet, MainView, Account, AlbumCell, CoverImage, Theme
```

## Composição e estado

`GramofoneApp` cria **cinco `ObservableObject`** e injeta por `environmentObject`:

| Objeto | Responsabilidade |
|---|---|
| `Session` | tokens, login/logout, sessão offline, perfil em cache |
| `PlayerController` | `AVPlayer` único, fila, repeat, snapshot, tela de bloqueio |
| `DownloadManager` | baixa álbuns, progresso, remoção |
| `ScrobbleQueue` | fila local de scrobbles + flush |
| `NetworkMonitor` | `NWPathMonitor` → `isOnline` |

A ligação entre eles acontece num único `.task` no `RootView`, **nesta ordem** (importa):

```swift
scrobbles.configure(session: session)
downloads.configure(session: session)
await session.restoreOnce()          // 1º: sessão (define o client HTTP)
player.configure(session:…, scrobbles:…, network:…)  // 2º: player precisa do client
scrobbles.startAutoFlush()
await scrobbles.flush()
```

`player.configure` restaura a fila do snapshot, e restaurar faixas de streaming exige o `client`
da sessão — por isso a ordem acima.

## Sessão (`Core/Session.swift`)

- Access token JWT (1 h) **só em memória**; refresh token (365 dias) no **Keychain**
  (`AfterFirstUnlock` → renova com a tela bloqueada).
- Renovação **rotativa**: cada `POST /auth/refresh` devolve um token novo, que é persistido.
- `authorized { client, token in … }` injeta o Bearer e, em **401**, renova e repete **uma vez**.
- **Sessão offline**: o perfil (`PublicUser`) é cacheado em `UserDefaults`. Se a renovação falhar
  por **rede**, o app entra com esse perfil (`isOfflineSession = true`) em vez de mandar para o
  login. Só desloga em **401 de verdade**.
- `revalidate()` é chamado quando `NetworkMonitor` volta a ficar online: tenta renovar; se der 401,
  aí sim encerra.

Consequência: sem rede o app abre, mostra **Baixados** e toca o que está no disco; qualquer chamada
de API falha com mensagem clara até reconectar.

## Player (`Player/PlayerController.swift`)

- **Um único `AVPlayer`**; trocar de faixa é `replaceCurrentItem` (não recria o player).
- `AVAudioSession` em `.playback` + `UIBackgroundModes: audio` → toca com a tela apagada.
- `MPNowPlayingInfoCenter` publica título/artista/álbum/capa/posição e
  `MPRemoteCommandCenter` trata play/pause/next/prev/seek da tela de bloqueio.
- **Resolução da faixa** (`resolveURL`): 1º arquivo baixado (manifesto em `OfflineStore`), 2º
  streaming `/api/media/<filePath>`. Arquivo apagado do disco cai para streaming automaticamente.
- **Fila**: array `[QueueItem]` + índice; `append` (sem duplicar), `playShuffled`, `jump`,
  `next`/`previous` (com repeat `off/one/all`). Persistida em `Documents/queue.json` a cada 5 s e
  no `scenePhase == .background`; ao abrir, **reaparece pausada no ponto salvo** (sem autoplay).
- **Ouvida e scrobble**: ao iniciar a faixa, `POST /plays` e `now-playing` (best-effort). Um
  acumulador de **tempo realmente tocado** dispara o scrobble quando passa de
  `min(duração/2, 4 min)` e a faixa tem **> 30 s** (regra do Last.fm). `playId` por ouvida;
  repeat-one reinicia a ouvida. Ao trocar de faixa, o pendente é finalizado.

## Offline (`Core/OfflineStore.swift`, `Offline/DownloadManager.swift`)

```
Documents/albums/<albumId>/
├── 01 - Título.mp3 …        # uma por faixa, nome derivado de número + título
├── cover.jpg                # capa do cache do servidor
└── manifest.json            # { albumId, title, artist, year, savedAt, tracks[] }
```

- `manifest.json` é a fonte de verdade do que está baixado; `OfflineStore.all()` lê todos.
- `DownloadManager` baixa faixa a faixa (progresso `done/total`), grava a capa e só então grava o
  manifesto (arquivo pela metade não conta como baixado).
- `AlbumView` tem **caminho offline**: se existe manifesto, monta o detalhe localmente
  (`OfflineDetail.swift`), sem tocar na API — é o que permite navegar e tocar sem rede.
- "Tocar tudo" (aba Baixados) junta todas as faixas baixadas, ordenadas por título do álbum; o
  "Aleatório" embaralha essa mesma fila.

## Scrobble (`Player/ScrobbleQueue.swift`)

- Fila em `Documents/scrobble-queue.json`, item `{playId, title, artist, album, duration, startedAt}`.
- Envio **em ordem**, um por vez; remove o item **só após 2xx**. O backend é idempotente por `playId`.
- Regras de parada: **401** ou **rede/5xx/429** → mantém a fila e tenta depois; **4xx de recusa**
  (faixa curta, timestamp velho, duplicado) → descarta para não travar a fila.
- Gatilhos de flush: ao enfileirar, após `restore`/login, ao voltar do background, quando a rede
  volta, e **timer de 60 s** enquanto online (o iOS nem sempre entrega o evento de caminho).
- **Conta → “Enviar scrobbles agora”** força a drenagem e mostra a contagem pendente.

## UI e navegação

- `RootView` escolhe entre `ProgressView`, `LoginView` e `MainView` conforme `session.state`.
- `MainView` = `LibraryView` + **mini player** via `safeAreaInset(edge: .bottom)` + player em
  `fullScreenCover`. **Não há `TabView`** de propósito: no iOS 15 a barra inferior brigaria com o
  mini player na tela de 320 pt do iPod.
- `LibraryView`: segmentado **Biblioteca | Baixados**, busca com debounce (350 ms), paginação de
  24, ordenação por `⋯` (título/artista/ano/adicionado + direção, persistida em `UserDefaults`) e
  `≡` para as listas.
- Detalhes (`AlbumView`, `AlbumListPage`, `SongListPage`) usam `NavigationLink` na forma
  **eager** (`destination:label:)`) — a forma com closure só existe no iOS 16.

## Compatibilidade iOS 15 (armadilhas já tratadas)

| API | Situação |
|---|---|
| `NavigationStack` / `NavigationSplitView` | iOS 16 — usar `NavigationView` |
| `NavigationLink { } label: { }` | iOS 16 — usar `NavigationLink(destination:label:)` |
| `LabeledContent`, `ContentUnavailableView`, `@Observable`, `SwiftData` | iOS 16/17 — não usar |
| `.task`, `.safeAreaInset`, `.searchable`, `AsyncImage`, `.tint` | iOS 15 ✅ |
| `AVAudioApplication` | iOS 17 — usar `AVAudioSession` |

## Limitações conhecidas

- **Sem download em background**: o download precisa do app aberto (fase futura: `URLSession`
  background).
- **Sem Background Sync**: a fila de scrobble sobe quando o app roda (timer/foreground).
- Cota de armazenamento do app é a do aparelho — não há limite artificial, mas também não há
  gerenciamento por cota além de “remover download”.
- Sem sweep automático de arquivos órfãos: se um MP3 for apagado por fora, a faixa cai para
  streaming e falha offline (mensagem clara).
