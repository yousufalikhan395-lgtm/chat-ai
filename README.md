# AI Chat Client

Multi-model chat client with cloud API and local Ollama support. Terminal-based with an OpenAI-compatible proxy for integration with tools like OpenCode.

## Features

- **Cloud API** — Access GPT 5.5, Claude Opus 4.7, Gemini 3.5 Flash, and 30+ models via the cloud API
- **Pro access** — The `is_vip=1` flag is sent automatically, unlocking all models
- **Local Ollama** — Fall back to a local Ollama instance on your network
- **Streaming responses** — Real-time token-by-token output
- **Conversation context** — Full multi-turn conversation tracking via `chat_id`
- **OpenAI-compatible proxy** — Translates OpenAI API format to the cloud backend, enabling integration with OpenCode, Cursor, etc.
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
| `BASE_URL` | *(set in config.py)* | Cloud API base URL |
| `IS_VIP` | `"1"` | Pro access flag |
| `OLLAMA_HOST` | `192.168.100.125` | Ollama server address |
| `OLLAMA_PORT` | `11434` | Ollama server port |

## Android App (`ai_chat_app/`)

A Flutter-based Android app that uses the same cloud API directly (no proxy needed).

### Features

- **40+ models** including GPT 5.5, Claude Opus 4.7, Gemini 3.5 Flash, Grok, Image Gen
- **Image upload** — Send photos to vision-capable models (camera & gallery)
- **Image generation** — Generate images from text prompts, view inline thumbnails
- **Document support** — Send PDFs (works with sm-agent, sm-pdf bots)
- **Markdown rendering** — Code blocks, lists, links rendered in chat
- **Dark theme** — Full Material 3 dark mode
- **Streaming responses** — Real-time token streaming
- **Conversation history** — Saved locally, browsable history screen
- **English titles** — Auto-generated from first message

### Build

```bash
cd ai_chat_app
snap run flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

### APK (pre-built)

Latest release build: [`ai_chat_v5-release.apk`](./ai_chat_v5-release.apk) (50MB)

### Structure

| File | Purpose |
|---|---|
| `lib/main.dart` | App entry + theme config |
| `lib/services/api_service.dart` | API client (auth, chat, streaming) |
| `lib/services/storage_service.dart` | Local message persistence |
| `lib/screens/chat_screen.dart` | Main chat UI + bot selector + history |
| `lib/models/bot_model.dart` | Bot metadata (mime support, type) |
| `lib/models/chat_message.dart` | Message data model |

## Files (Python)

| File | Purpose |
|---|---|
| `main.py` | Terminal chat interface |
| `chat.py` | Cloud API client (streaming + sync) |
| `auth.py` | Device + email authentication |
| `proxy.py` | OpenAI-compatible API proxy |
| `config.py` | Configuration constants |
| `ollama.py` | Local Ollama client |
