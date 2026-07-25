import json, uuid, hmac, hashlib, re
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse
import requests

from config import BASE_URL, VER_API, PLATFORM, VERSION_APP, IS_VIP

SIGN_KEY = "NEWWAY-SM-HUNGMANH-CHATAI"
PACKAGE = "newway.open.chatgpt.ai.chat.bot.free"
SALT = "AA:41:A5:CB:23:F5:F8:24:32:09:36:41:NW:13:69:69:32:5D:C8:B6:32:CC:47:90:SM:28:0F:3F:40:32:02:FF"

PROXY_TOKEN = None
PROXY_SESSION = requests.Session()
BOT_CACHE = {}
CHAT_IDS = {}

def _sign(msg):
    return hmac.new(SIGN_KEY.encode(), f"{SALT}&{msg}&{PACKAGE}".encode(), hashlib.sha256).hexdigest()

def auth():
    global PROXY_TOKEN
    uid = str(uuid.uuid4())
    r = PROXY_SESSION.post(f"{BASE_URL}/api/user/identifier", json={"uuid": uid, "platform": PLATFORM})
    data = r.json()
    PROXY_TOKEN = data["data"]["token"]
    PROXY_SESSION.headers.update({"Authorization": f"Bearer {PROXY_TOKEN}"})

def fetch_bots():
    global BOT_CACHE
    r = PROXY_SESSION.get(f"{BASE_URL}/api/{VER_API}/general/services_v2")
    data = r.json().get("data", {})
    for section in ["featured_bots", "official_bots", "aistore_bots", "new_tools_bots"]:
        for b in data.get(section, []):
            bid = b.get("bot_id")
            if bid:
                BOT_CACHE[bid] = b
    return BOT_CACHE

def resolve_model(model):
    if model in BOT_CACHE:
        return BOT_CACHE[model]
    for bid, bot in BOT_CACHE.items():
        if bot.get("model") == model or bot.get("name", "").lower() == model.lower():
            return bot
    return None

def _session_key(model_id, messages):
    first_user = ""
    for m in messages:
        if m["role"] == "user":
            first_user = m.get("content", "")
            break
    key = f"{model_id}:{first_user}"[:128]
    return hashlib.md5(key.encode()).hexdigest()

def _tools_to_text(tools):
    lines = ["\nYou have access to the following tools. When you need to use a tool, respond with:"]
    lines.append('<tool_call>{"name": "tool_name", "arguments": {"arg1": "val1"}}</tool_call>')
    for t in tools:
        fn = t.get("function", {})
        name = fn.get("name", "?")
        desc = fn.get("description", "")
        params = fn.get("parameters", {}).get("properties", {})
        req = fn.get("parameters", {}).get("required", [])
        lines.append(f"\n- {name}: {desc}")
        for pname, pinfo in params.items():
            r = " (required)" if pname in req else ""
            lines.append(f"  {pname}: {pinfo.get('description', '')}{r}")
    return "\n".join(lines)

def _extract_json_objects(text, start_tag="<tool_call>"):
    """Find JSON objects between start_tag and optionally end_tag using brace-depth parsing.
    Handles JSON content that may contain <, >, {, } inside string values."""
    results = []
    idx = 0
    while True:
        start = text.find(start_tag, idx)
        if start == -1:
            break
        # Find the first { after the tag
        brace_start = text.find("{", start + len(start_tag))
        if brace_start == -1:
            break
        depth = 0
        in_str = False
        escape = False
        end = -1
        for i in range(brace_start, len(text)):
            ch = text[i]
            if escape:
                escape = False
                continue
            if ch == "\\" and in_str:
                escape = True
                continue
            if ch == '"' and not escape:
                in_str = not in_str
                continue
            if not in_str:
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
                    if depth == 0:
                        end = i
                        break
        if end == -1:
            break
        raw_json = text[brace_start:end+1]
        try:
            obj = json.loads(raw_json)
            results.append((start, end+1, obj))
        except:
            pass
        idx = end + 1
    return results

def _parse_tool_calls(text):
    extracted = _extract_json_objects(text)
    calls = []
    for start, end, obj in extracted:
        try:
            calls.append({
                "id": f"call_{uuid.uuid4().hex[:12]}",
                "type": "function",
                "function": {
                    "name": obj["name"],
                    "arguments": json.dumps(obj["arguments"]) if isinstance(obj["arguments"], dict) else obj["arguments"]
                }
            })
        except:
            pass
    return calls

def _strip_tool_calls(text):
    extracted = _extract_json_objects(text)
    if not extracted:
        return text.strip()
    result = []
    last = 0
    for start, end, _ in extracted:
        if start > last:
            result.append(text[last:start])
        last = end
    if last < len(text):
        result.append(text[last:])
    cleaned = "".join(result)
    cleaned = cleaned.replace("</tool_call>", "")
    return cleaned.strip()

def _chunk_text(text, size=20):
    for i in range(0, len(text), size):
        yield text[i:i+size]

class ProxyHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        print(f"  [{args[0]}] {args[1]} {args[2]}")

    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type, Authorization")
        self.end_headers()

    def do_GET(self):
        path = urlparse(self.path).path
        if path in ("/v1/models", "/models"):
            models = []
            for bid, bot in BOT_CACHE.items():
                models.append({
                    "id": bot.get("model", bid),
                    "object": "model",
                    "created": 0,
                    "owned_by": bot.get("service", "unknown"),
                    "bot_id": bid,
                })
            self._send_json({"object": "list", "data": models})
        elif path == "/health":
            self._send_json({"status": "ok", "token": bool(PROXY_TOKEN), "bots": len(BOT_CACHE)})
        else:
            self._send_json({"error": "not found"}, 404)

    def do_POST(self):
        path = urlparse(self.path).path

        if path == "/auth":
            auth()
            fetch_bots()
            self._send_json({"status": "ok", "token": PROXY_TOKEN[:20] + "..."})
            return

        if not PROXY_TOKEN:
            self._send_json({"error": "not authenticated. POST /auth first"}, 401)
            return

        if path in ("/v1/chat/completions", "/chat/completions"):
            content_len = int(self.headers.get("Content-Length", 0))
            body = json.loads(self.rfile.read(content_len).decode())
            messages = list(body.get("messages", []))
            model_id = body.get("model", "smagent-1.0")
            stream = body.get("stream", False)
            tools = body.get("tools", [])

            has_tools = bool(tools)
            max_tokens = body.get("max_tokens")

            sys_prompt = ""
            tool_results = []
            user_msg = ""
            for m in messages:
                role = m["role"]
                content = m.get("content", "")
                if isinstance(content, list):
                    texts = [c["text"] for c in content if c.get("type") == "text"]
                    content = " ".join(texts)
                if role == "system":
                    sys_prompt = content
                elif role == "tool":
                    tool_results.append(content)
                elif role == "user":
                    user_msg = content

            if tool_results:
                context = "Tool results:\n" + "\n".join(f"- {r}" for r in tool_results)
                full_text = f"{context}\n\n{user_msg}"
            else:
                full_text = user_msg

            if sys_prompt or tool_results or has_tools:
                extra = ""
                if sys_prompt:
                    extra += sys_prompt + "\n"
                if has_tools:
                    extra += _tools_to_text(tools)
                elif tool_results:
                    extra += "\nYou have tools available. When you need to use a tool, respond with:\n<tool_call>{\"name\": \"tool_name\", \"arguments\": {...}}</tool_call>"
                full_text = f"{extra}\n\n{full_text}"

            bot = resolve_model(model_id)
            if not bot:
                bot = {"bot_id": "66446f6414e2f2ecdc0b1474", "service": "sm-agent", "model": "smagent-1.0"}

            bot_id = bot.get("bot_id")
            service = bot.get("service", "sm-agent")
            model = bot.get("model", "smagent-1.0")

            is_new_conv = all(m["role"] in ("system", "user") for m in messages)
            session_id = _session_key(model_id, messages)
            chat_key = f"{bot_id}:{session_id}"
            chat_id = None if is_new_conv else CHAT_IDS.get(chat_key)

            parts = {
                "message": (None, full_text),
                "model": (None, model),
                "service": (None, service),
                "signature": (None, _sign(full_text)),
                "stream": (None, "true" if stream else "false"),
                "platform": (None, PLATFORM),
                "version_app": (None, VERSION_APP),
                "is_vip": (None, IS_VIP),
                "bot_id": (None, bot_id),
            }
            if chat_id:
                parts["chat_id"] = (None, chat_id)
            if max_tokens:
                parts["max_tokens"] = (None, str(max_tokens))

            try:
                resp = PROXY_SESSION.post(
                    f"{BASE_URL}/api/{VER_API}/general/completionFast",
                    files=parts, stream=True, timeout=120
                )
                resp.raise_for_status()

                # Buffer ALL text from sboomtools — no live streaming
                first = True
                content_type = resp.headers.get("Content-Type", "")
                is_event_stream = "event-stream" in content_type or stream

                if is_event_stream:
                    full_buffer = ""
                    for line in resp.iter_lines(decode_unicode=True):
                        if not line:
                            continue
                        raw = line
                        if raw.startswith("data: "):
                            raw = raw[6:]
                        if raw == "[DONE]":
                            break
                        try:
                            chunk = json.loads(raw)
                            if first and "_id" in chunk and "text" not in chunk:
                                CHAT_IDS[chat_key] = chunk["_id"]
                                first = False
                                continue
                            first = False
                            full_buffer += chunk.get("text", "")
                        except:
                            pass
                else:
                    result = resp.json()
                    d = result.get("data", {})
                    full_buffer = d.get("content", "")
                    if d.get("created_chat"):
                        CHAT_IDS[chat_key] = d["created_chat"].get("_id")

                # Always parse tool calls — even when has_tools is False,
                # the model may still generate <tool_call> from its system prompt context
                # Always strip <tool_call> tags from displayed text (even if JSON parsing fails)
                tool_calls = _parse_tool_calls(full_buffer)
                clean_buffer = _strip_tool_calls(full_buffer)

                if stream:
                    self.send_response(200)
                    self.send_header("Content-Type", "text/event-stream")
                    self.send_header("Cache-Control", "no-cache")
                    self.send_header("Access-Control-Allow-Origin", "*")
                    self.end_headers()
                    self.wfile.flush()

                    for text_chunk in _chunk_text(clean_buffer):
                        oai = {
                            "id": f"chatcmpl-{uuid.uuid4().hex[:12]}",
                            "object": "chat.completion.chunk",
                            "created": 0,
                            "model": model,
                            "choices": [{"delta": {"content": text_chunk}, "index": 0, "finish_reason": None}]
                        }
                        self.wfile.write(f"data: {json.dumps(oai)}\n\n".encode())
                        self.wfile.flush()

                    if tool_calls:
                        for idx, tc in enumerate(tool_calls):
                            tcc = {
                                "id": f"chatcmpl-{uuid.uuid4().hex[:12]}",
                                "object": "chat.completion.chunk",
                                "created": 0,
                                "model": model,
                                "choices": [{
                                    "index": 0,
                                    "delta": {
                                        "role": "assistant",
                                        "content": None,
                                        "tool_calls": [{
                                            "index": idx,
                                            "id": tc["id"],
                                            "type": tc["type"],
                                            "function": tc["function"]
                                        }]
                                    }
                                }]
                            }
                            self.wfile.write(f"data: {json.dumps(tcc)}\n\n".encode())
                        finish = {
                            "id": f"chatcmpl-{uuid.uuid4().hex[:12]}",
                            "object": "chat.completion.chunk",
                            "created": 0,
                            "model": model,
                            "choices": [{"index": 0, "delta": {}, "finish_reason": "tool_calls"}]
                        }
                        self.wfile.write(f"data: {json.dumps(finish)}\n\n".encode())
                    else:
                        oai = {
                            "id": f"chatcmpl-{uuid.uuid4().hex[:12]}",
                            "object": "chat.completion.chunk",
                            "created": 0,
                            "model": model,
                            "choices": [{"delta": {}, "index": 0, "finish_reason": "stop"}]
                        }
                        self.wfile.write(f"data: {json.dumps(oai)}\n\n".encode())
                    self.wfile.write("data: [DONE]\n\n".encode())
                    self.wfile.flush()
                else:
                    msg = {"role": "assistant"}
                    if tool_calls:
                        msg["content"] = clean_buffer or None
                        msg["tool_calls"] = tool_calls
                    else:
                        msg["content"] = clean_buffer

                    oai_response = {
                        "id": f"chatcmpl-{uuid.uuid4().hex[:12]}",
                        "object": "chat.completion",
                        "created": 0,
                        "model": model,
                        "choices": [{"index": 0, "message": msg, "finish_reason": "tool_calls" if tool_calls else "stop"}],
                        "usage": {"prompt_tokens": 0, "completion_tokens": 0, "total_tokens": 0},
                    }
                    self._send_json(oai_response)
            except Exception as e:
                self._send_json({"error": str(e)}, 500)
        else:
            self._send_json({"error": "not found"}, 404)


if __name__ == "__main__":
    import sys
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8080

    print("Authenticating with sboomtools...")
    auth()
    print(f"  Token: {PROXY_TOKEN[:30]}...")
    print("Fetching available models...")
    bots = fetch_bots()
    for bid, bot in list(bots.items())[:5]:
        print(f"  {bot.get('name','?'):20s} -> {bot.get('model','?'):25s} ({bot.get('service','?')})")
    print(f"  ... and {len(bots)-5} more")

    server = HTTPServer(("0.0.0.0", port), ProxyHandler)
    print(f"\nOpenAI-compatible proxy running on http://localhost:{port}")
    print(f"  Endpoint: http://localhost:{port}/v1/chat/completions")
    print(f"  Fetch:    http://localhost:{port}/v1/models")
    print(f"  API Key:  any string (not validated)")
    print(f"  Tool calling: Supported (no raw XML in output)")
    print()
    server.serve_forever()
