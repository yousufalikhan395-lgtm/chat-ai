# AI Chat Client

Multi-model chat client with cloud API and local Ollama support. Terminal-based with an OpenAI-compatible proxy for integration with tools like OpenCode.

## Features

- **Cloud API** — Access GPT 5.5, Claude Opus 4.7, Gemini 3.5 Flash, and 30+ models via sboomtools
- **Pro access** — The `is_vip=1` flag is sent automatically, unlocking all models
- **Local Ollama** — Fall back to a local Ollama instance on your network
- **Streaming responses** — Real-time token-by-token output
- **Conversation context** — Full multi-turn conversation tracking via `chat_id`
- **OpenAI-compatible proxy** — Translates OpenAI API format to sboomtools, enabling integration with OpenCode, Cursor, etc.
- **Tool calling** — Supports function calling via `<tool_call>` XML tags parsed from model responses

## Quick Start

```bash
pip install requests
python main.py
```

Auto-authenticates via device ID. Commands:

| Command | Description |
|---|---|
| `/model <name>` | Switch model (default: smagent-1.0) |
| `/service <name>` | Switch service |
| `/bot <id>` | Switch bot |
| `/bots` | List available bots with IDs |
| `/new` | Start new conversation |
| `/ollama [model]` | Switch to local Ollama (default: llama3) |
| `/cloud` | Switch back to cloud API |
| `/login` | Login with email/password |
| `/help` | Show all commands |

## Proxy

The proxy provides an OpenAI-compatible API at `localhost:8080`:

```bash
python proxy.py
```

```bash
curl http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-5.5",
    "messages": [{"role": "user", "content": "Hello"}]
  }'
```

### Endpoints
- `GET /v1/models` — List available models
- `POST /v1/chat/completions` — Chat completions (streaming + non-streaming, tool calling)
- `GET /health` — Health check

### OpenCode integration
Add this to `opencode.json`:

```json
{
  "provider": {
    "sboomtools": {
      "npm": "@ai-sdk/openai-compatible",
      "name": "sboomtools",
      "options": {
        "baseURL": "http://localhost:8080/v1"
      },
      "models": {
        "gpt-5.5": { "name": "GPT 5.5", "family": "openai", "tool_call": true },
        "claude-opus-4-7": { "name": "Claude Opus 4.7", "family": "openai", "tool_call": true }
      }
    }
  }
}
```

## Configuration

Set config variables in `config.py`:

| Variable | Default | Description |
|---|---|---|
| `BASE_URL` | `https://chatopenai.sboomtools.net` | Cloud API base URL |
| `IS_VIP` | `"1"` | Pro access flag |
| `OLLAMA_HOST` | `192.168.100.125` | Ollama server address |
| `OLLAMA_PORT` | `11434` | Ollama server port |

## Files

| File | Purpose |
|---|---|
| `main.py` | Terminal chat interface |
| `chat.py` | Cloud API client (streaming + sync) |
| `auth.py` | Device + email authentication |
| `proxy.py` | OpenAI-compatible API proxy |
| `config.py` | Configuration constants |
| `ollama.py` | Local Ollama client |
