import json
import hmac
import hashlib
import requests
from config import BASE_URL, VER_API, PLATFORM, VERSION_APP, FREE_BOT_ID, FREE_SERVICE, FREE_MODEL, IS_VIP

SIGN_KEY = "NEWWAY-SM-HUNGMANH-CHATAI"
PACKAGE = "newway.open.chatgpt.ai.chat.bot.free"
SALT = "AA:41:A5:CB:23:F5:F8:24:32:09:36:41:NW:13:69:69:32:5D:C8:B6:32:CC:47:90:SM:28:0F:3F:40:32:02:FF"

def _sign(message):
    content = f"{SALT}&{message}&{PACKAGE}"
    return hmac.new(SIGN_KEY.encode(), content.encode(), hashlib.sha256).hexdigest()

def _check(resp):
    result = resp.json()
    if result.get("code") != 200:
        msg = result.get("message") or result.get("error", {}).get("message", str(result))
        raise Exception(f"API error: {msg}")
    return result

class ChatClient:
    def __init__(self, token):
        self.token = token
        self.session = requests.Session()
        self.chat_id = None

    def _headers(self):
        return {"Authorization": f"Bearer {self.token}"}

    def new_chat(self):
        self.chat_id = None

    def send_stream(self, message, model=FREE_MODEL, service=FREE_SERVICE,
                    chat_id=None, bot_id=FREE_BOT_ID, **extra):
        url = f"{BASE_URL}/api/{VER_API}/general/completionFast"
        headers = self._headers()
        is_vip = extra.pop("is_vip", IS_VIP)
        chat_id = chat_id or self.chat_id
        parts = {
            "message": (None, message),
            "model": (None, model),
            "service": (None, service),
            "signature": (None, _sign(message)),
            "stream": (None, "true"),
            "platform": (None, PLATFORM),
            "version_app": (None, VERSION_APP),
            "is_vip": (None, is_vip),
        }
        if chat_id:
            parts["chat_id"] = (None, chat_id)
        if bot_id:
            parts["bot_id"] = (None, bot_id)
        for k, v in extra.items():
            parts[k] = (None, str(v))

        response = self.session.post(
            url, headers=headers, files=parts, stream=True, timeout=120
        )
        response.raise_for_status()
        first = True
        for line in response.iter_lines(decode_unicode=True):
            if line:
                raw = line
                if raw.startswith("data: "):
                    raw = raw[6:]
                if raw == "[DONE]":
                    break
                try:
                    chunk = json.loads(raw)
                    if first and "_id" in chunk and "text" not in chunk:
                        self.chat_id = chunk["_id"]
                        first = False
                        continue
                    first = False
                    if "text" in chunk:
                        if chunk.get("code") != 200:
                            err = chunk.get("error", {})
                            raise Exception(err.get("message", str(chunk)))
                        text = chunk.get("text", "")
                        if text:
                            yield chunk
                except json.JSONDecodeError:
                    pass

    def send_sync(self, message, model=FREE_MODEL, service=FREE_SERVICE,
                  chat_id=None, bot_id=FREE_BOT_ID, **extra):
        url = f"{BASE_URL}/api/{VER_API}/general/completionFast"
        headers = self._headers()
        is_vip = extra.pop("is_vip", IS_VIP)
        chat_id = chat_id or self.chat_id
        parts = {
            "message": (None, message),
            "model": (None, model),
            "service": (None, service),
            "signature": (None, _sign(message)),
            "stream": (None, "false"),
            "platform": (None, PLATFORM),
            "version_app": (None, VERSION_APP),
            "is_vip": (None, is_vip),
        }
        if chat_id:
            parts["chat_id"] = (None, chat_id)
        if bot_id:
            parts["bot_id"] = (None, bot_id)
        for k, v in extra.items():
            parts[k] = (None, str(v))

        response = self.session.post(url, headers=headers, files=parts, timeout=120)
        response.raise_for_status()
        result = _check(response)
        created = result.get("data", {}).get("created_chat")
        if created and created.get("_id"):
            self.chat_id = created["_id"]
        return result

    def get_conversations(self, page=1, last_synced_at=0):
        url = f"{BASE_URL}/api/conversations"
        params = {"page": page, "last_synced_at": last_synced_at}
        resp = self.session.get(url, headers=self._headers(), params=params, timeout=15)
        resp.raise_for_status()
        return _check(resp)

    def get_conversation(self, chat_id):
        url = f"{BASE_URL}/api/conversation"
        resp = self.session.get(url, headers=self._headers(),
                                params={"chat_id": chat_id}, timeout=15)
        resp.raise_for_status()
        return _check(resp)

    def delete_conversation(self, chat_id):
        url = f"{BASE_URL}/api/conversation"
        resp = self.session.delete(url, headers=self._headers(),
                                   data={"chat_id": chat_id}, timeout=15)
        resp.raise_for_status()
        return _check(resp)

    def update_conversation_title(self, chat_id, title):
        url = f"{BASE_URL}/api/update-conversation"
        resp = self.session.post(url, headers=self._headers(),
                                 data={"chat_id": chat_id, "title": title}, timeout=15)
        resp.raise_for_status()
        return _check(resp)

    def get_services(self):
        url = f"{BASE_URL}/api/{VER_API}/general/services_v2"
        resp = self.session.get(url, headers=self._headers(), timeout=15)
        resp.raise_for_status()
        return _check(resp)

    def get_bot_info(self, bot_id):
        url = f"{BASE_URL}/api/{VER_API}/general/bot/{bot_id}"
        resp = self.session.get(url, headers=self._headers(),
                                params={"platform": PLATFORM}, timeout=15)
        resp.raise_for_status()
        return _check(resp)
