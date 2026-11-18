# Build e publicação

Este documento descreve **como o `.ipa` sai do código** sem depender de um Mac físico — o ponto
central do projeto. Tudo roda em máquinas alugadas (CI), e a instalação é feita pelo TrollStore.

## Visão geral

```
project.yml ──xcodegen──▶ Gramofone.xcodeproj ──xcodebuild──▶ Gramofone.app
                                                                 │
                                            Payload/Gramofone.app  │
                                                     zip ──────────▼
                                                Gramofone.ipa (sem assinatura)
                                                                 │
                            ┌────────────────────────────────────┴─────────────┐
                            ▼                                                  ▼
              GitHub Release "ios-latest"                          Artefato da run (30 dias)
              URL pública e estável                                exige login no GitHub
                            │
                    Safari no iPod → TrollStore → instalar
```

## Por que não existe `.xcodeproj` no repositório

O projeto Xcode é **gerado pelo XcodeGen** a partir de `project.yml`. Motivo: criar/editar um
`.xcodeproj` exige Xcode (macOS). Com o `project.yml` versionado, qualquer máquina (inclusive o
CI) regenera o projeto de forma determinística, e o `.gitignore` ignora `*.xcodeproj`.

Consequência prática: **para mudar algo de projeto** (bundle id, versão, deployment target,
sources, Info.plist), edita-se `project.yml` — nunca o `.xcodeproj`.

```yaml
targets:
  Gramofone:
    type: application
    platform: iOS
    deploymentTarget: "15.0"          # iPod touch 7 para no 15.8.8
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.marciosouza.gramofone
        INFOPLIST_FILE: Gramofone/App/Info.plist
        GENERATE_INFOPLIST_FILE: NO
        ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon
        TARGETED_DEVICE_FAMILY: "1"    # só iPhone/iPod
        MARKETING_VERSION: "0.5.1"     # versão exibida
        CURRENT_PROJECT_VERSION: "7"   # build
```

## Os comandos, linha por linha

```bash
# 1. gera o .xcodeproj a partir do project.yml
xcodegen generate

# 2. compila Release para aparelho, sem assinatura
xcodebuild \
  -project Gramofone.xcodeproj \
  -scheme Gramofone \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  PROVISIONING_PROFILE_SPECIFIER="" \
  build

# 3. confere o que saiu (o alvo mínimo é o que garante o iOS 15)
APP="build/Build/Products/Release-iphoneos/Gramofone.app"
/usr/libexec/PlistBuddy -c "Print :MinimumOSVersion" "$APP/Info.plist"   # 15.0
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Info.plist" # dev.marciosouza.gramofone

# 4. empacota no formato .ipa
rm -rf Payload Gramofone.ipa
mkdir -p Payload
cp -R "$APP" Payload/
zip -qry Gramofone.ipa Payload
```

Por que cada flag:

| Flag | Motivo |
|---|---|
| `-sdk iphoneos` + `generic/platform=iOS` | compila para **aparelho** (arm64), não simulador |
| `-derivedDataPath build` | mantém os produtos em `build/Build/Products/Release-iphoneos` (previsível para o passo 3/4) |
| `CODE_SIGNING_ALLOWED=NO` + `_REQUIRED=NO` | nenhuma assinatura é aplicada |
| `CODE_SIGN_IDENTITY=""` | evita tentar o certificado local |
| `PROVISIONING_PROFILE_SPECIFIER=""` | idem para perfil de provisionamento |

**Por que sem assinatura funciona:** o TrollStore aplica a assinatura/fakesign na instalação
(usa o bug do CoreTrust). Não há App Store, Apple ID nem revisão no caminho.

## GitHub Actions

Arquivo: `.github/workflows/ios.yml`. Gatilhos: **push em `main`** e `workflow_dispatch`.

```yaml
jobs:
  build:
    runs-on: macos-15-intel
    timeout-minutes: 30
    permissions:
      contents: write        # necessário para publicar o release
```

### Por que `macos-15-intel` e não `macos-15`

- `macos-14` foi **aposentado em 02/11/2026**; jobs que pedem essa label falham/cancelam na hora.
- `macos-15` é **arm64** e sofreu com falta de capacidade: dois runs morreram com
  `The job was not acquired by Runner of type hosted even after multiple attempts` e
  `Due to capacity constraints, jobs targeting macOS arm64 runners may experience longer queue times`.
- `macos-15-intel` (x64, 4 vCPU/14 GB) é **outro pool** e compilou em 2 de 2 tentativas.
  Suporte até ~ago/2027.

### Steps

1. **Checkout** — `actions/checkout@v4`.
2. **Xcode** — imprime a versão (`xcodebuild -version`), útil no log.
3. **Instalar XcodeGen** — `brew install xcodegen`.
4. **Gerar o projeto** — `xcodegen generate`.
5. **Build** — o comando acima, com `2>&1 | tee build.log`.
6. **Resumo do build (só em falha)** — `if: failure()`: escreve as últimas 120 linhas de
   `build.log` no `$GITHUB_STEP_SUMMARY`. **Isso aparece na página pública da run**, então dá para
   diagnosticar sem baixar log (que exige autenticação).
7. **Conferir alvo mínimo** — imprime `MinimumOSVersion`, bundle id e versão. Se o alvo subir de
   15.0 por acidente, aparece aqui.
8. **Empacotar `.ipa`**.
9. **Guardar artefato** — `actions/upload-artifact@v4`, nome `Gramofone-ipa`, retenção 30 dias.
   **Baixar artefato exige login** (mesmo em repo público): por `curl` dá `401`.
10. **Publicar IPA em release** — o caminho público:

```bash
gh release delete ios-latest --yes --cleanup-tag 2>/dev/null || true
gh release create ios-latest Gramofone.ipa \
  --title "Gramofone iOS — build mais recente" \
  --notes "Versão X (build Y) · minOS 15.0 · commit abc1234"
```

A release `ios-latest` é **recriada a cada push**, então a URL é sempre a mesma e aponta para o
build mais novo:

```
https://github.com/MarcioABSouza/gramofone-ios/releases/download/ios-latest/Gramofone.ipa
```

Asset de release em repositório público **não pede login** (diferente do artefato) — é o que
permite baixar por `curl` e, principalmente, **baixar direto no iPod** pelo Safari.

### Pular o build ao commitar só documentação

O workflow roda a cada push em `main`. Para commits que não mudam código (docs, README), basta
incluir `[skip ci]` na mensagem — GitHub Actions e Codemagic respeitam essa marca:

```bash
git commit -m "docs: descreve o pipeline de build [skip ci]"
```

### Limite da API do GitHub

Consultar status de run sem token consome **60 requisições/hora**. Não faça polling agressivo:
cada `GET /actions/runs/:id` conta. Para ver o resultado, abra a página da run (não conta) ou
espere o e-mail de falha do GitHub.

## Codemagic (alternativa quando o GitHub trava)

Arquivo: `codemagic.yaml`. Existe porque a fila do GitHub para macOS é melhor-esforço.

- **Instância**: `mac_mini_m2`; plano free dá **500 min/mês** (build ~3–4 min).
- **Xcode**: `latest`. Se o runner não suportar deployment target 15, fixe `xcode: 16.4`.
- **Configuração**: no painel do app, escolher **`codemagic.yaml`** como fonte (o fluxo
  automático não serve: o projeto é gerado por XcodeGen).
- **Passos**: versão do Xcode → instalar XcodeGen → gerar → `xcodebuild` sem assinatura →
  conferir alvo → empacotar → `artifacts: Gramofone.ipa`.
- **Download**: pela aba de artifacts do painel (não é URL pública como o release do GitHub).

Erros de ambiente conhecidos:

| Mensagem | Correção |
|---|---|
| `machine type mac_mini_m2 is not available on your plan` | `instance_type: mac_mini_m1` |
| `deployment target 15.0 is not supported` | `environment.xcode: 16.4` |

## Versionamento

Dois lugares, sempre juntos:

1. `project.yml` → `MARKETING_VERSION` (versão) e `CURRENT_PROJECT_VERSION` (build).
2. Textos fixos nas telas: `Gramofone/UI/LoginView.swift` e `Gramofone/UI/AccountView.swift`
   (exibem “Gramofone iOS 0.5.1”).

O workflow imprime a versão compilada no step **Conferir alvo mínimo**, então dá para conferir que
o `.ipa` publicado corresponde ao commit.

## Verificação sem Mac (o que dá para checar)

Antes de gastar um build, essas checagens rodam em Linux:

```bash
# conteúdo do pacote
unzip -l Gramofone.ipa | head

# Info.plist do app (versão, alvo mínimo, ícone)
unzip -p Gramofone.ipa Payload/Gramofone.app/Info.plist > /tmp/app.plist
python3 -c "import plistlib;d=plistlib.load(open('/tmp/app.plist','rb'));print(d['CFBundleShortVersionString'], d['MinimumOSVersion'], d['CFBundleIcons'])"

# ícone: tem que ser RGB (3 canais) e sem alpha
node -e "require('sharp')('.../icon-1024.png').metadata().then(m=>console.log(m.width, m.channels, m.hasAlpha))"
```

O que **não** dá para checar sem compilar: erros de tipo. Para sintaxe existe
`tree_sitter`/`tree_sitter_swift` (parser), mas ele dá **falso-positivo** em `try? await` — ignore
erros em linhas com essa construção.

## Diagnóstico de falhas

| Sintoma | Causa | Ação |
|---|---|---|
| `job was not acquired by Runner` / cancelado após ~15 min | capacidade do pool arm64 | usar `macos-15-intel` ou Codemagic |
| `listener`/`macos-14` falha imediata | label aposentada (02/11/2026) | trocar de label |
| `deployment target 15.0 is not supported` | Xcode do runner abandonou iOS 15 | pinar Xcode no Codemagic; no GitHub, conferir a imagem |
| `multiple commands produce Info.plist` | XcodeGen incluindo o plist como recurso | `excludes: ["App/Info.plist"]` em `sources` |
| `401 Requires authentication` ao baixar | é o **artefato**, não o release | baixar `releases/download/ios-latest/…` |
| App instala mas sem ícone | cache do SpringBoard | TrollStore → *Refresh Icon Cache* |
| Ícone com borda preta | PNG do logo tem alpha e foi achatado em cor escura | achatar em `#dc2626` (full-bleed) |

## Limitações assumidas

- **Sem App Store**: distribuição só por TrollStore/`.ipa`. Sem atualização automática — cada
  versão é um `.ipa` novo.
- **Artefato expira em 30 dias**; o release `ios-latest` é permanente (até ser recriado).
- **Minutos de macOS** são o recurso escasso: no GitHub, o pool é melhor-esforço; no Codemagic,
  500 min/mês.
- Nada disso exige Mac ou iPhone físico.
