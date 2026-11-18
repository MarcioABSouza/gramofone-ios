# Gramofone iOS

Cliente iOS do [Gramofone](https://github.com/MarcioABSouza/gramofone) para **iPod touch 7 (iOS 15.8.8)**: toca a
biblioteca do servidor na LAN, baixa álbuns para offline e enfileira scrobbles para o Last.fm.

- **Sem Mac e sem iPhone**: compila no CI (GitHub Actions `macos-15`), instala pelo **TrollStore**.
- **Sem App Store**: o `.ipa` sai sem assinatura do workflow e é instalado no aparelho.
- **Sem backend novo**: consome apenas endpoints que já existem no Gramofone.

O plano completo (arquitetura, contrato da API, fases e riscos) está em [PLAN.md](./PLAN.md).

## Status

| Fase | Estado |
|---|---|
| 0 — app mínimo + `GET /api/health` | ✅ validada no iPod (18/11/2026) |
| 1 — login + sessão no Keychain (refresh rotativo) | ✅ validada no iPod (18/11/2026) |
| 2 — biblioteca + detalhe do álbum | 🚧 implementada, aguardando teste no aparelho |
| 3 — player + tela bloqueada | pendente |
| 4 — download + offline | pendente |
| 5 — fila de scrobble | pendente |
| 6 — acabamento | pendente |

O app abre na **Biblioteca** (álbuns com cópia no servidor, busca e paginação); tocar num álbum
abre as faixas; o botão de perfil mostra a conta e permite sair.

## Como o build sai daqui

O `.xcodeproj` **não é versionado**: `project.yml` (XcodeGen) é a fonte da verdade e o CI gera o
projeto. A cada push em `main` (ou `workflow_dispatch`), o workflow:

1. gera o projeto com `xcodegen generate`;
2. compila `Release` para device com `CODE_SIGNING_ALLOWED=NO`;
3. empacota `Payload/Gramofone.app` em `Gramofone.ipa`;
4. publica o `.ipa` como artefato `Gramofone-ipa` (30 dias).

## Instalar no iPod (uma vez)

TrollStore via **TrollRestore** (roda em Linux) — passo a passo em `PLAN.md` §Instalação. Depois:
baixar o `.ipa` no aparelho → TrollStore → *Install IPA*.

## Estrutura

```
project.yml                      # XcodeGen (fonte da verdade)
Gramofone/
  App/        GramofoneApp, RootView, Info.plist
  Core/       APIClient, Session, Keychain, Settings
  Models/     Auth, Library
  UI/         LoginView, LibraryView, AlbumView, AccountView, CoverImage, Theme
  Resources/  Assets.xcassets (ícone reaproveitado do frontend)
.github/workflows/ios.yml        # build + artefato
```
