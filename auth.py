import requests
import uuid
import hashlib
from config import BASE_URL, PLATFORM

DEVICE_UUID = str(uuid.uuid4())

def _check(resp):
    result = resp.json()
    if result.get("code") != 200:
        msg = result.get("message") or result.get("error", {}).get("message", str(result))
        raise Exception(f"API error: {msg}")
    return result

class AuthClient:
    def __init__(self):
        self.session = requests.Session()
        self.token = None

    def register(self, email, password, name):
        url = f"{BASE_URL}/api/user/register"
        data = {
            "email": email,
            "password": password,
            "password_confirmation": password,
            "name": name,
            "platform": PLATFORM,
        }
        resp = self.session.post(url, data=data, timeout=15)
        return _check(resp)

    def verify_email(self, email, code):
        url = f"{BASE_URL}/api/user/register/verify_v2"
        data = {
            "email": email,
            "verification_code": code,
            "platform": PLATFORM,
            "uuid": DEVICE_UUID,
        }
        resp = self.session.post(url, data=data, timeout=15)
        result = _check(resp)
        self.token = result["data"]["token"]
        return result

    def login(self, email, password):
        url = f"{BASE_URL}/api/user/login_email_v2"
        data = {
            "email": email,
            "password": password,
            "guest_id": 0,
            "platform": PLATFORM,
            "uuid": DEVICE_UUID,
        }
        resp = self.session.post(url, data=data, timeout=15)
        result = _check(resp)
        self.token = result["data"]["token"]
        return result

    def refresh_token(self):
        url = f"{BASE_URL}/api/user/refresh_token"
        headers = {"Authorization": f"Bearer {self.token}"}
        resp = self.session.post(url, headers=headers, timeout=15)
        result = _check(resp)
        if result.get("code") == 200:
            self.token = result["data"]["token"]
        return result

    def get_user_info(self):
        url = f"{BASE_URL}/api/user/info"
        headers = {"Authorization": f"Bearer {self.token}"}
        resp = self.session.get(url, headers=headers, timeout=15)
        return _check(resp)

    def identifier(self):
        url = f"{BASE_URL}/api/user/identifier"
        data = {"uuid": DEVICE_UUID, "platform": PLATFORM}
        resp = self.session.post(url, data=data, timeout=15)
        result = _check(resp)
        self.token = result["data"]["token"]
        return result
