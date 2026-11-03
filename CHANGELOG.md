# Changelog

## November 2026 hardening update

Changes since the first public version, after independent reviews:

**Setup (`setup.ps1`)**
- A fresh install asks for an access level and no longer silently defaults to full access to the whole PC:
  1. read-only, one folder (recommended);
  2. full tools, with the direct file tools and default working directory limited to one folder;
  3. full Windows-user access (advanced).
- `config.json` is written as UTF-8 without a BOM, and a BOM is tolerated when it is read.
- Setup stops with an error if the local health check or `tunnel-client doctor` fails, instead of printing "All set".
- Setup checks OpenAI's current public `tunnel-client` release, installs or updates it, and verifies the ZIP against `SHA256SUMS.txt`.
- Re-running setup stops the running copy before changing binaries or config; uninstall stops the whole process tree.
- The launcher `.vbs` is written as UTF-16 so folder paths with non-English letters work.

**Server and launcher (`server.mjs`, `start.mjs`)**
- Roots resolve NTFS junctions and reparse points (realpath), so a junction inside an allowed folder cannot be used to reach another folder through the direct file tools.
- The direct file tools refuse `.state` and `config.json`. **In full mode, `run` remains an unrestricted shell as your Windows user. Roots do not sandbox it, and it can read `.state`.**
- `expected_sha256` is rechecked after staging, immediately before replacement. This is optimistic concurrency protection, not a lock.
- `edit_file` is capped at 50 MB; `read_file` keeps its 50 MB cap.
- `calls.log` stores tool metadata and a SHA256/length fingerprint for shell commands, not the raw command text.
- UTF-8 decoding of command output handles split characters and flushes at the end.
- `start.mjs` exits with an error on a port conflict or when required tunnel files or secrets are missing, so the task can restart it. A tunnel-client spawn error triggers a restart with backoff.
- `test.mjs` uses `fileURLToPath`, so setup and tests work in folders with spaces or Unicode.

**Validation, on a real Windows PC**
- `npm ci`, PowerShell parser checks and Node syntax checks passed.
- `node test.mjs` reported ALL PASS. It covers Git Bash, PowerShell, UTF-8 output, space/Unicode paths, read/write/edit, stale-SHA refusal, binary round trip, secret-file refusal, read-only mode, background jobs, and a real NTFS junction escape test.
