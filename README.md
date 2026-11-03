# ChatGPT Windows Bridge

**Let a normal ChatGPT chat (web, iPhone or Android app, phone browser) run commands and edit files on your own Windows PC.**

It uses OpenAI's official **Secure MCP Tunnel**, so nothing on your PC is opened to the internet. A small client on your PC connects *out* to OpenAI, and ChatGPT reaches a local MCP server through it.

```
ChatGPT chat  (your custom MCP plugin)
   -> OpenAI Secure MCP Tunnel        (only your linked ChatGPT workspace can use it)
   <- tunnel-client.exe on your PC     (outbound HTTPS only, no open port)
   -> server.mjs on 127.0.0.1:8797     (secret URL path + bridge key header)
```

Tested on ChatGPT Plus from the web, the iPhone app and a phone browser, including with the **Instant** model.

## Why

- **Your PC, from anywhere.** Ask ChatGPT to run a script, fix a file or check a build on your Windows machine, from your phone.
- **It runs on normal chat usage, and Instant should stay outside the limits.** OpenAI's help article ([Understanding ChatGPT and Codex usage limits](https://help.openai.com/en/articles/20001625-understanding-chatgpt-and-codex-usage-limits)) says:
  - *"Starting in December, Plus, Pro, and Business plans' usage allowance will be shared across ChatGPT and Codex."*
  - *"Instant chat will not draw from your usage."*

  So from December, **Instant is likely the only way to use this without spending your shared allowance**. It works with Instant today. Limits change often, so check that page for the current rules.

## What ChatGPT can do

| Tool | What it does |
|---|---|
| `run` | Runs one command in Git Bash (default) or PowerShell. If it is still running after `wait_sec` (max 110 s), it is **not killed**: it becomes a background job. |
| `job_output` / `job_stop` | Gets new output from a job, or stops it. |
| `read_file` | Reads text with size and sha256, a range of lines, or any file as base64. |
| `write_file` | Writes a whole file atomically and refuses symlinks. With `expected_sha256` it refuses to overwrite a file that changed since it was read. |
| `edit_file` | Replaces an exact string. Handles CRLF files. |
| `list_dir` | Lists a folder, optionally recursively. |

Every tool call is logged locally in `.state/calls.log`.

## Setup: about 10 minutes

You need:
- Windows 10 or 11;
- [Node.js](https://nodejs.org) 20+;
- [Git for Windows](https://git-scm.com/download/win), for Git Bash;
- a ChatGPT account that can add custom MCP servers (Plugins → Add custom MCP server);
- an [OpenAI Platform](https://platform.openai.com) account. It's free to create, and the tunnel itself costs nothing.

**1. Create the tunnel** on [platform.openai.com](https://platform.openai.com):
- Go to **Settings → Organization → Tunnels** ([direct link](https://platform.openai.com/settings/organization/tunnels)) → **Create tunnel**. Link it to your **ChatGPT workspace**: for a personal Plus or Pro account, that's your personal workspace. Copy the tunnel ID (`tunnel_…`).
- Go to **API keys → Create new secret key → Restricted**. Give it only **Tunnels: Read + Use**, and copy the key (`sk-…`). This key can only run your tunnel: it cannot call models or spend money.

**2. Install on the PC.** In PowerShell:
```powershell
git clone https://github.com/MoEl80/chatgpt-windows-bridge
cd chatgpt-windows-bridge
powershell -ExecutionPolicy Bypass -File setup.ps1
```
`setup.ps1` does all of the following:
- checks Node.js and Git;
- installs dependencies;
- downloads OpenAI's `tunnel-client` and verifies it against the release's `SHA256SUMS.txt`;
- creates the local secrets;
- asks for the tunnel ID and the key (hidden input), then stores the key so that only your Windows user can read it;
- writes the tunnel profile;
- runs the self-test;
- installs a logon task, so the bridge starts with Windows.

**3. Connect ChatGPT** (web):
- Go to **Plugins → + → Add custom MCP server**.
- Give it a name, for example "My PC", set **Connection** to **Tunnel**, and pick your tunnel.
- For **Authentication**, choose **No authentication** (see the next section), tick **I understand and want to continue**, then **Create** and **Install**.
- In any chat, type `@`, pick your plugin, and ask, for example: *"@My PC run hostname"*.

Optional `setup.ps1` settings:
```powershell
setup.ps1 -Mode read                               # read-only: only read_file + list_dir
setup.ps1 -Roots C:\Projects,D:\Notes -Cwd C:\Projects   # allowed folders + default folder
setup.ps1 -NewSecrets                              # rotate the secret path and bridge key
```
These are saved in `config.json` (see `config.example.json`). Environment variables `CHATGPT_BRIDGE_PORT`, `CHATGPT_BRIDGE_MODE`, `CHATGPT_BRIDGE_ROOTS` (`;`-separated), `CHATGPT_BRIDGE_CWD` and `CHATGPT_BRIDGE_BASH` override it.

## Authentication: who can use your PC

ChatGPT offers two choices for a custom MCP server: **OAuth** or **No authentication**. OAuth needs a sign-in server that OpenAI can reach from the internet, which defeats the point of a private tunnel. This bridge therefore uses these layers:

| Layer | What it stops |
|---|---|
| **The tunnel is tied to your account.** Only the ChatGPT workspace you linked can see and use it, and running it needs your restricted key. | Everyone else on the internet. There is no public URL to find. |
| **Bridge key.** tunnel-client sends a secret `X-Bridge-Key` header on every request, and the server refuses any request without it (HTTP 401). | Other programs on your PC calling the server directly. |
| **Secret URL path.** The server answers only on `/<random 43-character secret>/mcp`; every other path returns 404. | Guessing or scanning the local port. |
| **Your choice of power.** `-Mode read` (no shell, no writes) and `-Roots` (allowed folders). | Mistakes. Note that in full mode `run` can still reach any folder, because a shell can. |
| **ChatGPT's confirmation.** ChatGPT asks before tool calls unless you pick "Always allow". | Surprise actions. |

So "No authentication" in ChatGPT does **not** mean anyone can use it. It means **anyone who can use your ChatGPT account** can. Two real risks remain:

- **Your ChatGPT account.** Protect it with 2FA. If you share your workspace, everyone in it can see your tunnel.
- **Prompt injection.** If ChatGPT reads a hostile web page or file in the same chat, hidden text could try to make it call these tools. Keep the plugin out of chats where you browse untrusted content, consider `-Mode read`, and watch what it runs.

**To cut it off instantly:** delete the tunnel or its key on platform.openai.com, or uninstall the plugin in ChatGPT. Locally, run `install-task.ps1 -Remove`.

## Operate

- **Health:** `curl http://127.0.0.1:8797/healthz` (server) and `http://127.0.0.1:8798/ui` (tunnel).
- **Restart:** `powershell -ExecutionPolicy Bypass -File restart.ps1`.
- **Logs:** `.state\` (`server.log`, `tunnel.log`, `calls.log`, `jobs\`). Never share this folder: it holds your secrets.
- **Tests:** `npm test` starts private copies of the server on free ports and checks every tool, the 401/404 protection, read-only mode and allowed folders.

## Lesson learned

We first exposed the server through a **Tailscale Funnel on port 10000**. ChatGPT never sent it a single request. The official Secure MCP Tunnel worked straight away and needs no public URL at all.

Related: [claude-cloud-windows-bridge](https://github.com/MoEl80/claude-cloud-windows-bridge) does the same job for Claude Code cloud sessions.

## License

MIT
