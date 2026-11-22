"""livo IA backend: holds the Anthropic key and relays one assistant turn at a time.

Tools are declared here but executed on the iPhone, against the local database: the app runs the
tool loop, so the user's records never live on this server. Each request carries the full
conversation (the app's copy) and gets back the assistant's content blocks unchanged.
"""

from __future__ import annotations

import hmac
import os
from typing import Any

import anthropic
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

MODEL = "claude-opus-5-5"

SYSTEM_PROMPT = """Você é o livo IA, assistente pessoal dentro do app livo ("Vida inteligente. Sua vida mais simples.").
Responda sempre em português do Brasil, com valores em reais (R$ 1.234,56) e datas no formato dd/mm/aaaa.

Você ajuda com finanças pessoais, tarefas, hábitos, metas, compras e registros de saúde do usuário.
Os dados ficam no iPhone do usuário; você só os enxerga pelas ferramentas.

Regras:
- Nunca invente valores, saldos, preços, registros de saúde ou qualquer dado que as ferramentas não retornaram.
  Se faltar informação, diga o que falta ou consulte a ferramenta adequada.
- Separe com clareza o que é registro real (veio das ferramentas), o que é estimativa (cálculo seu sobre esses
  registros) e o que é sugestão. Rotule estimativas e sugestões como tal.
- Para registrar ou criar algo, use as ferramentas de escrita. O app pede confirmação ao usuário antes de gravar;
  se ele recusar, aceite e não insista.
- Preços nas listas de compras foram informados pelo usuário, não consultados em lojas. Não afirme preço atual de mercado.
- Saúde: você pode resumir registros e dar orientações gerais de bem-estar, mas não faz diagnósticos nem
  recomendações clínicas. Para sintomas ou decisões médicas, oriente procurar um profissional.
- Antes de sugerir uma compra, considere o orçamento e o saldo quando disponíveis e mostre o impacto, sem impedir a decisão.
- Seja breve e direto; use listas curtas quando ajudarem.

A primeira mensagem do usuário em cada turno começa com a data e hora locais do aparelho."""

_PERIOD = {
    "type": "object",
    "properties": {
        "inicio": {"type": "string", "description": "Data inicial AAAA-MM-DD (inclusiva)"},
        "fim": {"type": "string", "description": "Data final AAAA-MM-DD (inclusiva)"},
    },
    "required": ["inicio", "fim"],
}

# Keep this list in the same order forever: it is part of the cached prompt prefix.
TOOLS: list[dict[str, Any]] = [
    {
        "name": "consultar_financas",
        "description": "Totais de receitas e despesas no período, despesas por categoria e orçamentos do mês. "
                       "Inclui lançamentos previstos (futuros) separados dos já realizados.",
        "input_schema": _PERIOD,
    },
    {
        "name": "consultar_saldos",
        "description": "Saldo atual de cada conta e cartão ativo, limite disponível e fatura atual dos cartões.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "listar_lancamentos",
        "description": "Lançamentos do período, opcionalmente filtrados por texto (descrição ou categoria).",
        "input_schema": {
            "type": "object",
            "properties": {**_PERIOD["properties"], "texto": {"type": "string"}},
            "required": ["inicio", "fim"],
        },
    },
    {
        "name": "listar_tarefas",
        "description": "Tarefas do usuário. filtro: 'pendentes', 'hoje' (vencem hoje ou atrasadas), 'atrasadas' ou 'concluidas'.",
        "input_schema": {
            "type": "object",
            "properties": {"filtro": {"type": "string", "enum": ["pendentes", "hoje", "atrasadas", "concluidas"]}},
            "required": ["filtro"],
        },
    },
    {
        "name": "consultar_metas",
        "description": "Metas com progresso, prazo, valor atual/alvo, etapas e tarefas ligadas.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "consultar_habitos",
        "description": "Hábitos ativos com frequência, registros no período atual, sequência atual e melhor sequência.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "consultar_saude",
        "description": "Registros manuais de saúde: valor por dia nos últimos N dias, média de 7 dias e meta diária.",
        "input_schema": {
            "type": "object",
            "properties": {
                "tipo": {"type": "string",
                         "enum": ["passos", "agua", "sono", "exercicio", "peso", "frequencia", "pressao", "cintura"]},
                "dias": {"type": "integer", "minimum": 1, "maximum": 90},
            },
            "required": ["tipo", "dias"],
        },
    },
    {
        "name": "listar_compras",
        "description": "Listas de compras e de desejos com itens pendentes, quantidade e preço informado pelo usuário.",
        "input_schema": {"type": "object", "properties": {}},
    },
    {
        "name": "registrar_despesa",
        "description": "Registra uma despesa (ou receita, se tipo='receita'). Requer confirmação do usuário no app. "
                       "Sem 'conta', usa a primeira conta ativa; sem 'data', usa hoje.",
        "input_schema": {
            "type": "object",
            "properties": {
                "valor": {"type": "number", "description": "Valor em reais, positivo (ex.: 75.5)"},
                "descricao": {"type": "string"},
                "categoria": {"type": "string", "description": "Nome de uma categoria existente"},
                "conta": {"type": "string", "description": "Nome de uma conta existente"},
                "data": {"type": "string", "description": "AAAA-MM-DD"},
                "tipo": {"type": "string", "enum": ["despesa", "receita"]},
            },
            "required": ["valor", "descricao"],
        },
    },
    {
        "name": "criar_tarefa",
        "description": "Cria uma tarefa. Requer confirmação do usuário no app.",
        "input_schema": {
            "type": "object",
            "properties": {
                "titulo": {"type": "string"},
                "prazo": {"type": "string", "description": "AAAA-MM-DD"},
                "prioridade": {"type": "string", "enum": ["baixa", "media", "alta"]},
            },
            "required": ["titulo"],
        },
    },
    {
        "name": "adicionar_item_compra",
        "description": "Adiciona um item a uma lista de compras, ou à lista de desejos se desejo=true. "
                       "Requer confirmação do usuário no app.",
        "input_schema": {
            "type": "object",
            "properties": {
                "nome": {"type": "string"},
                "desejo": {"type": "boolean"},
                "lista": {"type": "string", "description": "Nome de uma lista existente (opcional)"},
                "preco": {"type": "number", "description": "Preço unitário informado pelo usuário, em reais"},
            },
            "required": ["nome"],
        },
    },
]

MAX_MESSAGES = 200


class TurnRequest(BaseModel):
    # Anthropic message objects as the app stored them (assistant content echoed back unchanged).
    messages: list[dict[str, Any]] = Field(min_length=1, max_length=MAX_MESSAGES)


class TurnResponse(BaseModel):
    content: list[dict[str, Any]]
    stop_reason: str | None
    model: str


def allowed_tokens() -> list[str]:
    return [t.strip() for t in os.environ.get("LIVO_DEVICE_TOKENS", "").split(",") if t.strip()]


def require_device(authorization: str = Header(default="")) -> None:
    token = authorization.removeprefix("Bearer ").strip()
    if not token or not any(hmac.compare_digest(token, t) for t in allowed_tokens()):
        raise HTTPException(status_code=401, detail="Token do aparelho inválido.")


def get_client() -> anthropic.Anthropic:
    return anthropic.Anthropic()


app = FastAPI(title="livo IA")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/v1/assistant/turn", response_model=TurnResponse, dependencies=[Depends(require_device)])
def assistant_turn(req: TurnRequest, client: anthropic.Anthropic = Depends(get_client)) -> TurnResponse:
    try:
        response = client.beta.messages.create(
            model=MODEL,
            max_tokens=16000,
            system=SYSTEM_PROMPT,
            tools=TOOLS,
            messages=req.messages,
            output_config={"effort": "medium"},
            cache_control={"type": "ephemeral"},
            betas=["server-side-fallback-2026-07-01"],
            fallbacks="default",
        )
    except anthropic.BadRequestError as e:
        raise HTTPException(status_code=400, detail=f"Requisição inválida: {e.message}") from e
    except anthropic.RateLimitError as e:
        raise HTTPException(status_code=429, detail="Limite de uso atingido. Tente em instantes.") from e
    except anthropic.APIStatusError as e:
        raise HTTPException(status_code=502, detail=f"Erro no serviço de IA ({e.status_code}).") from e
    except anthropic.APIConnectionError as e:
        raise HTTPException(status_code=503, detail="Sem conexão com o serviço de IA.") from e

    data = response.to_dict()
    return TurnResponse(content=data["content"], stop_reason=data.get("stop_reason"), model=data.get("model", MODEL))
