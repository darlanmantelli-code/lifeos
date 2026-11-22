"""Runs the real Anthropic SDK against a mocked HTTP transport: checks what we send and what we return."""

import json

import anthropic
import httpx2
import pytest
from fastapi.testclient import TestClient

import assistant

CANNED = {
    "id": "msg_test",
    "type": "message",
    "role": "assistant",
    "model": "claude-opus-5-5",
    "content": [
        {"type": "thinking", "thinking": "", "signature": "sig"},
        {"type": "text", "text": "Vou consultar seus gastos."},
        {"type": "tool_use", "id": "toolu_1", "name": "consultar_financas",
         "input": {"inicio": "2026-11-01", "fim": "2026-11-30"}},
    ],
    "stop_reason": "tool_use",
    "stop_sequence": None,
    "usage": {"input_tokens": 10, "output_tokens": 5},
}


@pytest.fixture
def api(monkeypatch):
    monkeypatch.setenv("LIVO_DEVICE_TOKENS", "tok-a, tok-b")
    sent = {}

    def handler(request: httpx2.Request) -> httpx2.Response:
        sent["url"] = str(request.url)
        sent["headers"] = request.headers
        sent["body"] = json.loads(request.content)
        return httpx2.Response(200, json=CANNED)

    def fake_client():
        return anthropic.Anthropic(api_key="test", http_client=httpx2.Client(transport=httpx2.MockTransport(handler)))

    assistant.app.dependency_overrides[assistant.get_client] = fake_client
    yield TestClient(assistant.app), sent
    assistant.app.dependency_overrides.clear()


def test_rejects_missing_or_wrong_token(api):
    client, _ = api
    body = {"messages": [{"role": "user", "content": "oi"}]}
    assert client.post("/v1/assistant/turn", json=body).status_code == 401
    assert client.post("/v1/assistant/turn", json=body, headers={"Authorization": "Bearer nope"}).status_code == 401


def test_turn_relays_request_and_content(api):
    client, sent = api
    messages = [{"role": "user", "content": "22/11/2026 10:00\nQuanto gastei em alimentação neste mês?"}]
    r = client.post("/v1/assistant/turn", json={"messages": messages}, headers={"Authorization": "Bearer tok-b"})
    assert r.status_code == 200, r.text

    body = sent["body"]
    assert sent["url"].endswith("/v1/messages")
    assert body["model"] == "claude-opus-5-5"
    assert body["messages"] == messages
    assert body["system"] == assistant.SYSTEM_PROMPT
    assert [t["name"] for t in body["tools"]] == [t["name"] for t in assistant.TOOLS]
    assert body["fallbacks"] == "default"
    assert body["output_config"] == {"effort": "medium"}
    assert "thinking" not in body  # adaptive by default on this model
    assert "server-side-fallback-2026-07-01" in sent["headers"]["anthropic-beta"]

    out = r.json()
    assert out["stop_reason"] == "tool_use"
    assert out["content"] == CANNED["content"]  # echoed unchanged, thinking block included


def test_empty_conversation_rejected(api):
    client, _ = api
    r = client.post("/v1/assistant/turn", json={"messages": []}, headers={"Authorization": "Bearer tok-a"})
    assert r.status_code == 422


def test_tool_names_unique_and_system_prompt_is_static():
    names = [t["name"] for t in assistant.TOOLS]
    assert len(names) == len(set(names))
    # Volatile data (date/time) must not be in the cached prefix.
    assert "2026" not in assistant.SYSTEM_PROMPT
