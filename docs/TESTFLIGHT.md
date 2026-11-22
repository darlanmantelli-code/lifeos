# Instalar o livo pelo TestFlight

O envio é feito pelo GitHub Actions (macOS), sem precisar de Mac. Você faz a parte de conta e credenciais uma vez;
depois cada envio é um clique.

## 1. Conta Apple Developer (uma vez)

1. Inscreva-se no Apple Developer Program: <https://developer.apple.com/programs/> (US$ 99/ano).
2. Anote o **Team ID** em <https://developer.apple.com/account> → Membership details.

## 2. Identificador e app no App Store Connect (uma vez)

1. Escolha um **bundle ID único** no seu domínio invertido, por exemplo `br.seunome.livo`
   (`com.livo.app`, o padrão do projeto, provavelmente já pertence a outra pessoa).
2. Em <https://developer.apple.com/account/resources/identifiers> → **+** → App IDs → App,
   registre esse bundle ID (capacidades: nenhuma extra por enquanto).
3. Em <https://appstoreconnect.apple.com> → Apps → **+** → Novo app: plataforma iOS, nome **livo**
   (se estiver ocupado, use algo como "livo – sua vida"), idioma Português (Brasil), o bundle ID acima e um SKU qualquer (ex.: `livo-001`).

## 3. Chave da API do App Store Connect (uma vez)

1. App Store Connect → Usuários e acesso → **Integrações** → Chaves da API da App Store Connect → **+**.
2. Nome `github-actions`, acesso **Admin** (necessário para a assinatura gerenciada na nuvem criar o certificado de distribuição).
3. Baixe o arquivo `AuthKey_XXXX.p8` (só pode ser baixado uma vez) e anote o **Key ID** e o **Issuer ID**.

## 4. Segredos no GitHub (uma vez)

No repositório → Settings → Secrets and variables → Actions → **New repository secret**:

| Segredo | Valor |
|---|---|
| `APPLE_TEAM_ID` | Team ID |
| `APP_BUNDLE_ID` | O bundle ID do passo 2 |
| `ASC_KEY_ID` | Key ID |
| `ASC_ISSUER_ID` | Issuer ID |
| `ASC_KEY_P8` | Conteúdo inteiro do arquivo `.p8` (incluindo as linhas BEGIN/END) |

Esses valores ficam só nos segredos do GitHub, nunca no código.

## 5. Enviar uma versão

GitHub → Actions → **TestFlight** → Run workflow. Em ~15 minutos o build aparece no App Store Connect → TestFlight
(o processamento da Apple pode levar mais alguns minutos). O número do build é o número da execução do workflow.

## 6. Instalar no iPhone

1. App Store Connect → TestFlight → **Testes internos** → crie um grupo e adicione seu e-mail da conta Apple.
2. No iPhone, instale o app **TestFlight** da App Store e aceite o convite.
3. Na primeira vez, o build pede a resposta de conformidade de exportação: o app declara
   `ITSAppUsesNonExemptEncryption = NO` (usa só HTTPS padrão), então normalmente nada é perguntado.

## 7. Depois de instalar

- Configurações (Início → menu ▦ → Configurações): ative o bloqueio por Face ID e faça um primeiro backup.
- livo IA: suba o servidor (`backend/README.md`) e informe URL e token na aba IA.
- Modo demonstração: disponível nas Configurações para explorar com dados fictícios.

## Problemas comuns

| Erro | Causa provável |
|---|---|
| `No profiles for '...' were found` | Bundle ID não registrado (passo 2.2) ou diferente do segredo `APP_BUNDLE_ID` |
| `Cloud signing permission error` | Chave da API sem acesso Admin |
| `The bundle version must be higher` | Reexecute o workflow (o número do build sobe a cada execução) |
| App não aparece no TestFlight | Aguarde o processamento; verifique o e-mail da Apple sobre o build |
