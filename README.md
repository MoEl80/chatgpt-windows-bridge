# ChatGPT Windows Bridge

**Use ChatGPT on your phone or the web to run commands and edit files on your Windows PC.**

You type in a normal ChatGPT chat, for example *"run my backup script"* or *"fix the typo in notes.txt"*, and it happens on your PC.

```
ChatGPT (phone or web)  ->  OpenAI's tunnel  ->  small program on your PC  ->  your files
```

It uses OpenAI's own **Secure MCP Tunnel**. Your PC opens no ports and gets no public address.

## Why it's useful

- **Your PC from anywhere:** the ChatGPT web, the iPhone or Android app, or a phone browser.
- **Works with the Instant model.** OpenAI says that from December 2026 ChatGPT and Codex will share one usage allowance, but *"Instant chat will not draw from your usage"* ([OpenAI help page](https://help.openai.com/en/articles/20001625-understanding-chatgpt-and-codex-usage-limits)). So Instant should let you use this without spending that allowance.

Tested on ChatGPT Plus (web, iPhone app, phone browser), including Instant.

## Setup

You need Windows, [Node.js](https://nodejs.org) and [Git for Windows](https://git-scm.com/download/win).

**1. On [platform.openai.com](https://platform.openai.com)** (free):
- Open **[Tunnels](https://platform.openai.com/settings/organization/tunnels)**, click **Create tunnel**, link it to your ChatGPT account, and copy the tunnel ID (`tunnel_…`).
- Open **API keys**, create a **Restricted** key with only **Tunnels: Read + Use**, and copy it (`sk-…`). This key can't spend money.

**2. On your PC**, in PowerShell:
```powershell
git clone https://github.com/MoEl80/chatgpt-windows-bridge
cd chatgpt-windows-bridge
powershell -ExecutionPolicy Bypass -File setup.ps1
```
Paste the tunnel ID and the key when it asks. The script installs everything, tests it, and makes it start with Windows.

**3. In ChatGPT (web):**
- Go to **Plugins → + → Add custom MCP server**.
- Name it, for example "My PC". Set **Connection** to **Tunnel** and pick your tunnel. Set **Authentication** to **No authentication**.
- Tick the box, then click **Create** and **Install**.

Done. In any chat, type `@My PC` and ask, for example: *"run hostname"*.

## Is it safe?

- Only **your** ChatGPT account can use your tunnel.
- ChatGPT can do anything **your Windows user** can do. Turn on 2FA for ChatGPT.
- Don't use it in the same chat as web pages or files you don't trust: hidden text in them could try to trick ChatGPT.
- To limit it, use one of these setup options:
  - `setup.ps1 -Mode read`: ChatGPT can only look at files, not change or run anything.
  - `setup.ps1 -Roots C:\Projects`: only that folder.
- **To turn it off:** uninstall the plugin in ChatGPT, or delete the tunnel on platform.openai.com.

## If something's wrong

- Check `http://127.0.0.1:8797/healthz`. It should say `ok`.
- Restart with `powershell -ExecutionPolicy Bypass -File restart.ps1`.
- Logs are in the `.state` folder. Don't share that folder: it holds your secrets.

Also see [claude-cloud-windows-bridge](https://github.com/MoEl80/claude-cloud-windows-bridge), the same idea for Claude Code.

## License

MIT
