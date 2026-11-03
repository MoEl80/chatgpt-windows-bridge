# ChatGPT Windows Bridge

**Use ChatGPT on your phone or the web to run commands and edit files on your Windows PC.**

You type in a normal ChatGPT chat, for example *"run my backup script"* or *"fix the typo in notes.txt"*, and it happens on your PC.

```
ChatGPT (phone or web)  ->  OpenAI's tunnel  ->  small program on your PC  ->  your files
```

It uses OpenAI's own **Secure MCP Tunnel**. Nothing on your PC can be reached from the internet: it only makes an outbound connection to OpenAI. Your PC must be **on and logged in** for it to work.

*An unofficial community project, not made by OpenAI.*

## Why it's useful

- **Your PC from anywhere:** the ChatGPT web, the iPhone or Android app, or a phone browser.
- **Works with the Instant model.** Note on usage, as of November 2026: OpenAI's [help page](https://help.openai.com/en/articles/20001625-understanding-chatgpt-and-codex-usage-limits) says that from December ChatGPT and Codex will share one usage allowance, and that *"Instant chat will not draw from your usage"*. Rules change, so check that page.

Tested on ChatGPT Plus (web, iPhone app, phone browser), including Instant.

## Setup

You need Windows 10 or 11, [Node.js](https://nodejs.org) 20 or newer, and [Git for Windows](https://git-scm.com/download/win). After installing them, close and reopen PowerShell. No administrator rights are needed.

**1. On [platform.openai.com](https://platform.openai.com)** (free):
- Open **[Tunnels](https://platform.openai.com/settings/organization/tunnels)**, click **Create tunnel**, link it to your ChatGPT account, and copy the tunnel ID (`tunnel_…`).
- Open **API keys**, create a **Restricted** key with only **Tunnels: Read + Use**, and copy it (`sk-…`). This key can only use your tunnel.

**2. On your PC**, open **Windows PowerShell** (Start menu → type *PowerShell*) and run:
```powershell
git clone https://github.com/MoEl80/chatgpt-windows-bridge
cd chatgpt-windows-bridge
powershell -ExecutionPolicy Bypass -File setup.ps1
```
Paste the tunnel ID and the key when it asks. **The key does not show on screen while you paste it; that's normal, just press Enter.** The script installs everything, tests it, and starts the bridge now and every time you log in.

**3. In ChatGPT (web):**
- Go to **Plugins → + → Add custom MCP server**.
- Name it, for example "My PC". Set **Connection** to **Tunnel** and pick your tunnel. Set **Authentication** to **No authentication**.
- Tick **I understand and want to continue**, then click **Create** and **Install**. (Menu names may change slightly over time.)

Done. In any chat, type `@My PC` and ask, for example: *"run hostname"*.

## Is it safe?

- Only the ChatGPT account linked to your tunnel can use it.
- ChatGPT can do anything **your Windows user** can do, and what it reads is sent to OpenAI. Turn on 2FA for ChatGPT, and keep ChatGPT's "allow" prompts on.
- Don't use it in the same chat as web pages, emails or files from strangers: hidden text in them could try to trick ChatGPT.
- **Want it safer?** Re-run setup with one of these options:
  - `powershell -ExecutionPolicy Bypass -File setup.ps1 -Mode read`: ChatGPT can only look at files. It can't change anything or run commands. This is the real safety switch.
  - `powershell -ExecutionPolicy Bypass -File setup.ps1 -Roots C:\Projects`: the file tools only work inside that folder. Commands could still reach other folders, so combine it with `-Mode read` if you need a strict limit.
- The bridge never lets ChatGPT read its own secret files.

**To turn it off for good:**
1. Run `powershell -ExecutionPolicy Bypass -File install-task.ps1 -Remove`.
2. Delete the folder.
3. Uninstall the plugin in ChatGPT, and delete the tunnel and key on platform.openai.com.

## If something's wrong

- Check `http://127.0.0.1:8797/healthz` (8797 is the default port). It should say `ok`.
- "Port already in use" in `.state\server.log`: run `restart.ps1`.
- "could not start" in `.state\server.log`: your antivirus may have blocked `tunnel\tunnel-client.exe`.
- **To update:** run `git pull`, then run `setup.ps1` again.
- Restart with `powershell -ExecutionPolicy Bypass -File restart.ps1`.
- Logs are in the `.state` folder. Don't share that folder: it holds your secrets.

Also see [claude-cloud-windows-bridge](https://github.com/MoEl80/claude-cloud-windows-bridge), the same idea for Claude Code.

## License

MIT
