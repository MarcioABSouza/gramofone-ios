# Gramofone iOS

Cliente iOS do [Gramofone](https://github.com/MarcioABSouza/gramofone) para **iPod touch 7 (iOS
15.8.8)**: toca a biblioteca do servidor na LAN, baixa álbuns para ouvir offline, navega listas e
envia os scrobbles ao Last.fm — inclusive os ouvidos sem conexão.

**A restrição que definiu o projeto: nada de Mac físico e nada de iPhone.** O app compila em CI
(GitHub Actions / Codemagic) e é instalado pelo **TrollStore**, sem Apple ID, sem App Store e sem
revisão. O backend não muda: o app consome só endpoints que já existem.

## Instalar

No **Safari do iPod**:

```
https://github.com/MarcioABSouza/gramofone-ios/releases/download/ios-latest/Gramofone.ipa
```

→ **Baixar** → Arquivos → TrollStore → **+**. Instalar por cima preserva sessão e downloads.

Primeira vez no aparelho (TrollStore) e opção de servir o `.ipa` pela LAN: **[docs/INSTALL.md](docs/INSTALL.md)**.

## O que o app faz

| Área | Recurso |
|---|---|
| Sessão | login, refresh rotativo no Keychain (365 d) e **modo offline** com perfil em cache |
| Biblioteca | grade, busca, paginação, **ordenação** (título/artista/ano/adicionado) |
| Listas | álbuns e músicas; **Tocar** e **Aleatório** (embaralha as faixas) |
| Álbum | Tocar · Aleatório · **Adicionar à fila** · Baixar para offline |
| Baixados | grade offline, **Tocar tudo**, Aleatório, remover download |
| Player | fila persistente, áudio em segundo plano, tela de bloqueio, repeat, seek |
| Last.fm | scrobble com fila local, envio automático ao reconectar + envio manual |

Escopo consciente: **não** tem criação/edição de listas, cifras, notas, favoritos ou avaliações —
o web e o app Android cobrem isso.

## Como o build sai daqui

O `.xcodeproj` **não é versionado**: `project.yml` (XcodeGen) é a fonte da verdade e o CI gera o
projeto. Cada push em `main` compila `Release` para device **sem assinatura**, empacota
`Payload/` em `Gramofone.ipa`, guarda como artefato (30 dias) e **recria a release `ios-latest`**
com URL pública.

```bash
xcodegen generate
xcodebuild -project Gramofone.xcodeproj -scheme Gramofone -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Detalhes (flags, runner `macos-15-intel`, por que não arm64, release x artefato, Codemagic,
diagnóstico de falhas): **[docs/BUILD.md](docs/BUILD.md)**.

## Estrutura

```
project.yml                     # XcodeGen — projeto, versão, bundle, deployment target
codemagic.yaml                  # build alternativo (quando o GitHub fica sem runner)
.github/workflows/ios.yml       # build + release do .ipa
Gramofone/
  App/        GramofoneApp, RootView, Info.plist
  Core/       APIClient, Session, Keychain, Settings, OfflineStore, NetworkMonitor
  Models/     Auth, Library, Lists
  Player/     PlayerController, QueueItem, ScrobbleQueue
  Offline/    DownloadManager, OfflineDetail
  UI/         Login, Library, Album, Lists, AlbumListPage, SongListPage, Player, MiniPlayer,
              MainView, Account, AlbumCell, CoverImage, Theme
  Resources/  Assets.xcassets (ícone full-bleed #dc2626, derivado do frontend)
```

## Documentação

| Documento | Conteúdo |
|---|---|
| [docs/BUILD.md](docs/BUILD.md) | pipeline completo, comandos, CI, versões, diagnóstico |
| [docs/INSTALL.md](docs/INSTALL.md) | TrollStore via TrollRestore, instalação, primeiros passos |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | camadas, sessão offline, player, fila de scrobble, iOS 15 |
| [docs/API.md](docs/API.md) | endpoints usados, formatos e armadilhas de contrato |
| [docs/CHANGELOG.md](docs/CHANGELOG.md) | histórico 0.1.0 → 0.5.1 |
| [PLAN.md](PLAN.md) | plano original (fases e critérios de aceite) |

## Status

Todas as fases do plano concluídas e validadas no aparelho — versão atual **0.5.1 (build 7)**.
