import json
import requests
from config import OLLAMA_HOST, OLLAMA_PORT

BASE_URL = f"http://{OLLAMA_HOST}:{OLLAMA_PORT}"
DEFAULT_MODEL = "llama3"

class OllamaClient:
    def __init__(self, base_url=BASE_URL):
        self.base_url = base_url.rstrip("/")

    def send_stream(self, message, model=DEFAULT_MODEL):
        url = f"{self.base_url}/v1/chat/completions"
        payload = {
            "model": model,
            "messages": [{"role": "user", "content": message}],
            "stream": True,
        }
        resp = requests.post(url, json=payload,
                             headers={"Content-Type": "application/json"},
                             stream=True, timeout=60)
        resp.raise_for_status()
        for line in resp.iter_lines(decode_unicode=True):
            if line and line.startswith("data: "):
                data_str = line[6:]
                if data_str.strip() == "[DONE]":
                    break
                try:
                    data = json.loads(data_str)
                    if "choices" in data and data["choices"]:
                        delta = data["choices"][0].get("delta", {})
                        content = delta.get("content", "")
                        if content:
                            yield content
                except json.JSONDecodeError:
                    pass

    def send_sync(self, message, model=DEFAULT_MODEL):
        url = f"{self.base_url}/v1/chat/completions"
        payload = {
            "model": model,
            "messages": [{"role": "user", "content": message}],
            "stream": False,
        }
        resp = requests.post(url, json=payload,
                             headers={"Content-Type": "application/json"},
                             timeout=60)
        resp.raise_for_status()
        data = resp.json()
        return data["choices"][0]["message"]["content"]

    def list_models(self):
        url = f"{self.base_url}/api/tags"
        resp = requests.get(url, timeout=15)
        resp.raise_for_status()
        return resp.json()

    def health(self):
        try:
            resp = requests.get(self.base_url, timeout=5)
            return resp.status_code == 200
        except requests.RequestException:
            return False
