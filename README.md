# Gramofone iOS

Cliente iOS do [Gramofone](https://github.com/) para **iPod touch 7 (iOS 15.8.8)**: toca a
biblioteca do servidor na LAN, baixa álbuns para offline e enfileira scrobbles para o Last.fm.

- **Sem Mac e sem iPhone**: compila no CI (GitHub Actions `macos-14`), instala pelo **TrollStore**.
- **Sem App Store**: o `.ipa` sai sem assinatura do workflow e é instalado no aparelho.
- **Sem backend novo**: consome apenas endpoints que já existem no Gramofone.

O plano completo (arquitetura, contrato da API, fases e riscos) está em [PLAN.md](./PLAN.md).

## Status

**Fase 0 implementada** — app "hello" que testa a conexão com o servidor (`GET /api/health`),
validando a cadeia CI → IPA → TrollStore → rede no aparelho.

Tela única: campo com o endereço do servidor (padrão `http://192.168.0.100:8998`), botão
**Testar conexão** e o resultado. O endereço fica salvo em `UserDefaults`.

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
  Core/       APIClient, Settings
  Resources/  Assets.xcassets (ícone reaproveitado do frontend)
.github/workflows/ios.yml        # build + artefato
```
