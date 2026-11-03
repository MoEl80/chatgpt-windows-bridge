# ChatGPT Windows Bridge

**Let a normal ChatGPT conversation run commands and work with files on your own Windows PC through OpenAI's Secure MCP Tunnel.**

You type in a ChatGPT chat, for example *"run my backup script"* or *"fix the typo in notes.txt"*, and the installed plugin can do it on your PC.

```text
ChatGPT  ->  OpenAI Secure MCP Tunnel  ->  tunnel-client on your PC  ->  local MCP server  ->  your files
```

This bridge opens **no inbound internet port**. OpenAI's `tunnel-client` makes an outbound HTTPS connection to OpenAI and forwards tunnel requests to the MCP server listening only on `127.0.0.1`. Your PC must be **on and logged in** for the normal scheduled-task setup to work.

*An unofficial community project, not made by OpenAI.*

## Availability

OpenAI's current documentation says full custom MCP support is available to **ChatGPT Business and Enterprise/Edu** on the web; **Pro** can connect custom MCP servers with read/fetch permissions. Availability and workspace permissions can change.

This project was also tested successfully on **one ChatGPT Plus account on 3 November 2026**, including write tools and invocation from the iPhone app/browser after setup on the web. Treat that as an observed account-specific result, not a promise that every Plus account has the same MCP access.

The bridge itself works with whatever ChatGPT model/account is allowed to call the installed plugin. A dated usage note: as of November 2026, OpenAI's usage documentation says Instant chat does not draw from the shared ChatGPT/Codex usage allowance that begins in December; rules can change, so check the current OpenAI help page.

## Setup

You need Windows 10 or 11, [Node.js](https://nodejs.org) 20 or newer, and [Git for Windows](https://git-scm.com/download/win). After installing them, close and reopen PowerShell. No administrator rights are needed.

### 1. Create the OpenAI tunnel

On [platform.openai.com](https://platform.openai.com):

- Open **Tunnels**, create a tunnel, associate it with the Platform organization / ChatGPT workspace that should use it, and copy the tunnel ID (`tunnel_…`).
- Create a **Restricted** runtime API key with only **Tunnels: Read + Use** and copy it (`sk-…`). Those permissions apply at the Platform-organization level; the key is not cryptographically limited by this repo to one tunnel, so treat it as a secret.

### 2. Install the bridge on the PC

Open **Windows PowerShell** (Start menu → type *PowerShell*) and run:

```powershell
git clone https://github.com/MoEl80/chatgpt-windows-bridge
cd chatgpt-windows-bridge
powershell -ExecutionPolicy Bypass -File setup.ps1
```

Paste the tunnel ID and API key when asked. **The API key does not appear on screen while you paste it; that is normal — press Enter.**

On a fresh install, setup asks you to choose:

1. **Read-only, one folder — recommended.** Only `read_file` and `list_dir` are exposed.
2. **Full tools, one folder for direct file tools/default working directory.** `run` is still an unrestricted shell as your Windows user and is **not sandboxed by Roots**.
3. **Full tools, whole Windows user account — advanced.** ChatGPT can do anything that Windows user can do.

The installer then:

- installs Node dependencies;
- downloads or updates to OpenAI's latest public `tunnel-client` release and verifies its release ZIP against `SHA256SUMS.txt`;
- creates local bridge secrets with restricted NTFS permissions;
- writes `config.json` as UTF-8 without a BOM;
- runs the local end-to-end self-test;
- installs/starts the per-user logon task unless `-NoTask` is used;
- requires the local health check and `tunnel-client doctor` to pass before it prints **All set**.

Re-running `setup.ps1` keeps your bridge secrets unless you pass `-NewSecrets`, stops the scheduled copy before changing binaries/config, and updates `tunnel-client` when OpenAI has a newer public release.

### 3. Add it in ChatGPT

Custom MCP creation is configured on **ChatGPT web** and depends on your account/workspace permissions. In the current Plugins experience:

- Open **Plugins → + → Add custom MCP server**.
- Give it a name such as `My PC`.
- Set **Connection** to **Tunnel** and choose your tunnel.
- Set **Authentication** to **No authentication** for this local MCP endpoint; the Secure MCP Tunnel and its OpenAI organization/workspace permissions remain the access boundary.
- Review the warning, then create/install the plugin.

Menu names can change over time. After installation, use `@My PC` (or your chosen name) in a chat and ask, for example: *"run hostname"*.

## Security: understand the two modes

ChatGPT tool calls execute on your **real Windows PC**.

### Read-only mode

Run:

```powershell
powershell -ExecutionPolicy Bypass -File setup.ps1 -Mode read -Roots C:\Projects
```

Only `read_file` and `list_dir` are offered. The bridge:

- limits those tools to the configured Roots;
- resolves NTFS junctions/reparse points before allowing access, so a junction inside an allowed root cannot be used to escape to another folder;
- refuses its own `.state` secret files and `config.json` through the direct file tools.

This is the safer mode when you only need ChatGPT to inspect files.

### Full mode

Full mode adds `run`, `write_file`, `edit_file`, `job_output` and `job_stop`.

**Important:** `run` is an unrestricted Git Bash / Windows PowerShell command running as your Windows user. `Roots` restricts the direct file tools and the command's working directory; it **cannot sandbox paths referenced inside the command itself**. A shell command can therefore access anything that Windows user can access, including this bridge's `.state` folder.

The direct `read_file`, `write_file` and `edit_file` tools still refuse `.state` and `config.json`, resolve junctions, stage writes, and support `expected_sha256` stale-write checks. Those SHA checks are optimistic concurrency protection, not a filesystem lock.

### General precautions

- Tunnel access follows the Platform organizations / ChatGPT workspaces associated with the tunnel plus their permissions; do not assume it means only one personal ChatGPT account can ever use it.
- Turn on strong account security / MFA where available.
- Keep ChatGPT confirmation/allow prompts enabled for risky actions.
- Do not combine powerful PC access with untrusted web pages, emails or files unless you are prepared for prompt-injection risk. Hidden text can try to persuade the model to use tools in ways you did not intend.
- In full mode, consider running the bridge under a dedicated standard Windows account if you need a real OS-level boundary around what the shell can access.
- `.state` contains credentials and operational logs. Do not share it.
- `calls.log` stores tool metadata and a SHA256/length fingerprint for shell commands, **not the raw command text**.

## File safety details

- Direct file writes are staged beside the destination and then renamed.
- `expected_sha256` is checked **after staging, immediately before replacement**, reducing the stale-write race. It is not a lock against a writer racing the final check/rename.
- Symlink destinations are refused.
- Allowed-root checks resolve existing junctions/reparse points and the nearest existing parent for new paths.
- `edit_file` is for UTF-8 text and is capped at 50 MB. Editing arbitrary non-UTF-8 text safely is still a known limitation; use binary/base64 workflows or a deliberate shell command when appropriate.

## Turning it off

To stop and remove the automatic bridge task:

```powershell
powershell -ExecutionPolicy Bypass -File install-task.ps1 -Remove
```

Then, for a complete cut-off:

1. Delete the local bridge folder if you no longer need it.
2. Remove/unpublish the ChatGPT plugin as appropriate for your account/workspace.
3. Delete or disassociate the OpenAI tunnel.
4. Revoke/delete the restricted tunnel API key.

## If something is wrong

- Check `http://127.0.0.1:8797/healthz` (8797 is the default port). It should say `ok`.
- Check `.state\server.log` and `.state\tunnel.log`.
- **Port already in use:** run `powershell -ExecutionPolicy Bypass -File restart.ps1`, or rerun setup with another `-Port`.
- **tunnel-client could not start:** antivirus/security software may have blocked `tunnel\tunnel-client.exe`.
- **Missing bridge/tunnel files:** rerun `setup.ps1`; `start.mjs` now exits loudly instead of leaving a healthy-looking local server with no tunnel.
- **Update:** run `git pull`, then rerun `setup.ps1`. Setup checks OpenAI's latest public `tunnel-client` release and updates it when needed.
- Restart manually with `powershell -ExecutionPolicy Bypass -File restart.ps1`.

Also see [claude-cloud-windows-bridge](https://github.com/MoEl80/claude-cloud-windows-bridge), the Tailscale + SSH version for Claude Code cloud sessions.

## License

MIT
