# Servidor do livo IA

Guarda a chave da API da Anthropic e repassa cada turno da conversa ao modelo (`claude-opus-5-5`).
As ferramentas rodam **no iPhone**, sobre o banco local: o servidor não guarda dados do usuário nem conversas.

## Variáveis de ambiente

| Variável | O que é |
|---|---|
| `ANTHROPIC_API_KEY` | Chave da API (console.anthropic.com). Nunca vai para o app. |
| `LIVO_DEVICE_TOKENS` | Tokens aceitos, separados por vírgula. Gere um por aparelho: `python -c "import secrets; print(secrets.token_urlsafe(32))"` |

## Rodar localmente

```
py -m venv .venv
./.venv/Scripts/pip install -r requirements.txt
./.venv/Scripts/python -m pytest -q
$env:ANTHROPIC_API_KEY="..."; $env:LIVO_DEVICE_TOKENS="..."; ./.venv/Scripts/uvicorn assistant:app --port 8000
```

## Docker

```
docker build -t livo-ia .
docker run -d -p 8000:8000 -e ANTHROPIC_API_KEY=... -e LIVO_DEVICE_TOKENS=... livo-ia
```

Publique atrás de HTTPS (o app só aceita `https://`, ou `http://localhost` no simulador).
No app: aba **IA → ⋯ → Configurar servidor**, informe a URL e o token.

## Notas

- Fallback de recusa: `fallbacks: "default"` (beta `server-side-fallback-2026-07-01`) — se o modelo recusar por política, a API tenta outro modelo na mesma chamada.
- Esforço `medium`, cache automático do prompt (system + ferramentas são estáticos; a data vai na mensagem do usuário).
- Sem streaming nem limite de taxa por aparelho ainda: adicionar quando o uso pedir.
