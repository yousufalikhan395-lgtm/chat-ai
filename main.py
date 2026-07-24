import sys
import readline
from auth import AuthClient
from chat import ChatClient
from ollama import OllamaClient
from config import FREE_BOT_ID, FREE_SERVICE, FREE_MODEL, IS_VIP

def print_stream(stream_gen):
    full = []
    for chunk in stream_gen:
        text = chunk.get("text", "")
        print(text, end="", flush=True)
        full.append(text)
    print()
    return "".join(full)

def cmd_help():
    print("""Commands:
  /help               - Show this help
  /login              - Login with email/password
  /register           - Register a new account
  /verify             - Verify email with verification code
  /refresh            - Refresh auth token
  /identifier         - Get device-based token (no email needed)
  /model <name>       - Switch model (default: smagent-1.0)
  /service <name>     - Switch service (default: sm-agent)
  /bot <bot_id>       - Switch bot (default: 66446f... free bot)
  /bots               - List available bots with IDs
  /new                - Start new conversation (clear context)
  /ollama [model]     - Use local Ollama (default: llama3)
  /cloud              - Switch back to cloud API
  /conversations      - List conversations
  /info               - Show user info
  /quit               - Exit""")

def main():
    auth = AuthClient()
    chat_client = None
    use_ollama = False
    ollama = OllamaClient()
    current_model = FREE_MODEL
    current_service = FREE_SERVICE
    current_bot_id = FREE_BOT_ID

    # Auto-login via device identifier (no email required)
    try:
        auth.identifier()
        chat_client = ChatClient(auth.token)
        print(f"AI Chat Client — Pro mode (is_vip={IS_VIP}) via device ID")
    except Exception as e:
        print(f"AI Chat Client - auth failed: {e}")
    print("Type /help for commands, /quit to exit\n")

    while True:
        try:
            text = input("You: ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break

        if not text:
            continue

        if text.startswith("/"):
            parts = text.split(maxsplit=1)
            cmd = parts[0].lower()
            arg = parts[1] if len(parts) > 1 else ""

            if cmd == "/quit":
                break
            elif cmd == "/help":
                cmd_help()
            elif cmd == "/login":
                email = input("  Email: ").strip()
                pw = input("  Password: ").strip()
                try:
                    auth.login(email, pw)
                    chat_client = ChatClient(auth.token)
                    use_ollama = False
                    print("  Logged in!")
                except Exception as e:
                    print(f"  Error: {e}")
            elif cmd == "/register":
                email = input("  Email: ").strip()
                pw = input("  Password: ").strip()
                name = input("  Name: ").strip()
                try:
                    auth.register(email, pw, name)
                    print("  Registered! Check email for verification code.")
                except Exception as e:
                    print(f"  Error: {e}")
            elif cmd == "/verify":
                email = input("  Email: ").strip()
                code = input("  Code: ").strip()
                try:
                    auth.verify_email(email, code)
                    chat_client = ChatClient(auth.token)
                    use_ollama = False
                    print("  Verified and logged in!")
                except Exception as e:
                    print(f"  Error: {e}")
            elif cmd == "/refresh":
                try:
                    auth.refresh_token()
                    chat_client = ChatClient(auth.token)
                    print("  Token refreshed!")
                except Exception as e:
                    print(f"  Error: {e}")
            elif cmd == "/model":
                if arg:
                    current_model = arg
                    print(f"  Model: {current_model}")
                else:
                    print(f"  Current model: {current_model}")
            elif cmd == "/service":
                if arg:
                    current_service = arg
                    print(f"  Service: {current_service}")
                else:
                    print(f"  Current service: {current_service}")
            elif cmd == "/ollama":
                model = arg if arg else "llama3"
                use_ollama = True
                print(f"  Using Ollama (model: {model})")
                if ollama.health():
                    print(f"  Ollama at {ollama.base_url} is reachable")
                else:
                    print(f"  Warning: Ollama at {ollama.base_url} not reachable")
            elif cmd == "/cloud":
                use_ollama = False
                if chat_client:
                    print("  Switched to cloud API")
                else:
                    print("  Not logged in. Use /login first.")
            elif cmd == "/new":
                if chat_client:
                    chat_client.new_chat()
                    print("  New conversation started")
                else:
                    print("  Not logged in.")
            elif cmd == "/bot":
                if arg:
                    current_bot_id = arg
                    print(f"  Bot ID: {current_bot_id}")
                else:
                    print(f"  Current bot ID: {current_bot_id}")
            elif cmd == "/bots":
                if not chat_client:
                    print("  Not logged in.")
                    continue
                try:
                    result = chat_client.get_services()
                    data = result.get('data', {})
                    for section in ['featured_bots', 'official_bots', 'aistore_bots', 'new_tools_bots']:
                        bots = data.get(section, [])
                        if bots:
                            print(f'  === {section} ===')
                            for b in bots:
                                bid = b.get('bot_id', b.get('_id', '?'))
                                name = b.get('name', '?')
                                svc = b.get('service', '?')
                                mod = b.get('model', '?')
                                print(f'  {bid} | {name} | svc={svc} mod={mod}')
                except Exception as e:
                    print(f"  Error: {e}")
            elif cmd == "/conversations":
                if not chat_client:
                    print("  Not logged in.")
                    continue
                try:
                    convs = chat_client.get_conversations()
                    print(f"  Conversations: {convs}")
                except Exception as e:
                    print(f"  Error: {e}")
            elif cmd == "/identifier":
                try:
                    auth.identifier()
                    chat_client = ChatClient(auth.token)
                    use_ollama = False
                    print("  Device token obtained!")
                except Exception as e:
                    print(f"  Error: {e}")
            elif cmd == "/info":
                if not chat_client:
                    print("  Not logged in.")
                    continue
                try:
                    info = auth.get_user_info()
                    print(f"  User info: {info}")
                except Exception as e:
                    print(f"  Error: {e}")
            else:
                print(f"  Unknown: {cmd}")
            continue

        if use_ollama:
            model = current_model if current_model.startswith("llama") else "llama3"
            try:
                for chunk in ollama.send_stream(text, model=model):
                    print(chunk, end="", flush=True)
                print()
            except Exception as e:
                print(f"  Error: {e}")
        else:
            if not chat_client:
                print("  Not logged in. Use /login or /register first.")
                continue
            try:
                gen = chat_client.send_stream(text, model=current_model, service=current_service, bot_id=current_bot_id)
                print("AI: ", end="")
                print_stream(gen)
            except Exception as e:
                print(f"  Error: {e}")

if __name__ == "__main__":
    import json
    main()
