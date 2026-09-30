"""web_app: serves the Assistant UI (Lambda Function URL). Renders the chat
page with the Cognito and REST API details baked in as environment variables.
"""
import os

API_ENDPOINT = os.environ["API_ENDPOINT"]
COGNITO_USER_POOL_ID = os.environ["COGNITO_USER_POOL_ID"]
COGNITO_CLIENT_ID = os.environ["COGNITO_CLIENT_ID"]
PROJECT_NAME = os.environ.get("PROJECT_NAME", "Semantic Search Assistant")


def lambda_handler(event, context):
    method = event.get("requestContext", {}).get("http", {}).get("method", "GET")
    if method != "GET":
        return {"statusCode": 405, "body": "Method not allowed"}

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "text/html"},
        "body": _render_page(),
    }


def _render_page():
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>{PROJECT_NAME}</title>
  <style>
    :root {{
      color-scheme: dark;
      --bg: #0f172a;
      --panel: rgba(15, 23, 42, 0.9);
      --text: #e2e8f0;
      --muted: #94a3b8;
      --accent: #22d3ee;
      --border: rgba(148, 163, 184, 0.22);
    }}
    * {{ box-sizing: border-box; }}
    body {{
      margin: 0;
      min-height: 100vh;
      font-family: Inter, ui-sans-serif, system-ui, -apple-system, "Segoe UI", sans-serif;
      color: var(--text);
      background: linear-gradient(135deg, #020617 0%, #0f172a 55%, #111827 100%);
      padding: 40px 20px;
    }}
    .shell {{
      max-width: 720px;
      margin: 0 auto;
      background: var(--panel);
      border: 1px solid var(--border);
      border-radius: 20px;
      padding: 32px;
    }}
    h1 {{ font-size: 1.8rem; margin-top: 0; }}
    p.lede {{ color: var(--muted); }}
    label {{ display: block; margin-top: 16px; font-size: 0.85rem; color: var(--muted); }}
    input {{
      width: 100%;
      margin-top: 6px;
      padding: 12px 14px;
      border-radius: 10px;
      border: 1px solid var(--border);
      background: rgba(255, 255, 255, 0.04);
      color: var(--text);
      font-size: 1rem;
    }}
    button {{
      margin-top: 20px;
      padding: 12px 20px;
      border: none;
      border-radius: 10px;
      background: var(--accent);
      color: #0f172a;
      font-weight: 700;
      cursor: pointer;
    }}
    button:disabled {{ opacity: 0.6; cursor: wait; }}
    #chat {{ margin-top: 20px; display: flex; flex-direction: column; gap: 12px; }}
    .msg {{ padding: 12px 14px; border-radius: 12px; line-height: 1.5; background: rgba(255, 255, 255, 0.05); }}
    .msg.user {{ background: rgba(34, 211, 238, 0.14); }}
  </style>
</head>
<body>
  <div class="shell">
    <h1>{PROJECT_NAME}</h1>
    <p class="lede">
      Sign in with your Cognito user pool credentials (pool <code>{COGNITO_USER_POOL_ID}</code>,
      client <code>{COGNITO_CLIENT_ID}</code>), paste the resulting ID token below, then ask a
      domain-specific question grounded in the enterprise knowledge base.
    </p>

    <label for="token">Cognito ID token</label>
    <input id="token" type="text" placeholder="eyJraWQ..." autocomplete="off" />

    <label for="prompt">Question</label>
    <input id="prompt" type="text" placeholder="e.g. What is our data retention policy?" autocomplete="off" />

    <button id="send" type="button">Ask assistant</button>

    <div id="chat"></div>
  </div>

  <script>
    const API_ENDPOINT = "{API_ENDPOINT}";
    const chat = document.getElementById("chat");
    const tokenInput = document.getElementById("token");
    const promptInput = document.getElementById("prompt");
    const sendButton = document.getElementById("send");

    sendButton.addEventListener("click", async () => {{
      const token = tokenInput.value.trim();
      const prompt = promptInput.value.trim();
      if (!token || !prompt) return;

      addMessage("user", prompt);
      promptInput.value = "";
      sendButton.disabled = true;

      try {{
        const response = await fetch(`${{API_ENDPOINT}}/search`, {{
          method: "POST",
          headers: {{
            "Content-Type": "application/json",
            "Authorization": `Bearer ${{token}}`,
          }},
          body: JSON.stringify({{ prompt }}),
        }});

        if (!response.ok) {{
          throw new Error(`Request failed with status ${{response.status}}`);
        }}

        const data = await response.json();
        addMessage("assistant", data.answer || JSON.stringify(data));
      }} catch (err) {{
        addMessage("assistant", `Error: ${{err.message}}`);
      }} finally {{
        sendButton.disabled = false;
      }}
    }});

    function addMessage(role, text) {{
      const el = document.createElement("div");
      el.className = `msg ${{role}}`;
      el.textContent = text;
      chat.appendChild(el);
      chat.scrollTop = chat.scrollHeight;
    }}
  </script>
</body>
</html>"""
