// ChatGPT Windows Bridge launcher (run by the logon task): starts the MCP server in-process
// and keeps OpenAI's tunnel-client (Secure MCP Tunnel, outbound-only) running next to it,
// restarting it if it exits. Logs: .state/server.log (this process) and .state/tunnel.log.
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { startHttp } from './server.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const STATE = path.join(HERE, '.state');
const EXE = path.join(HERE, 'tunnel', 'tunnel-client.exe');
const KEY_FILE = path.join(STATE, 'control-plane-api-key');
const PROFILE = path.join(STATE, 'tunnel-client.yaml'); // holds tunnel_id + local MCP URL (secret path)
const log = (m) => console.log(`${new Date().toISOString()} ${m}`);

try {
  const srv = await startHttp();
  log(`chatgpt-windows-bridge server listening on 127.0.0.1:${srv.address().port}`);
} catch (e) {
  log(e.code === 'EADDRINUSE'
    ? `FATAL: port ${e.port} is already in use. Another copy of the bridge (or another program) is running. Run restart.ps1, or pick another port with setup.ps1 -Port.`
    : `FATAL: server did not start: ${e.message}`);
  process.exit(1);
}

let child = null;
let stopping = false;
const stop = () => { stopping = true; try { if (child) spawn('taskkill', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true }); } catch {} setTimeout(() => process.exit(0), 500); };
process.once('SIGINT', stop);
process.once('SIGTERM', stop);

function runTunnel(attempt = 0) {
  if (stopping) return;
  const missing = [EXE, KEY_FILE, PROFILE].find((f) => !fs.existsSync(f));
  if (missing) { log(`tunnel not started: missing ${missing} (run setup.ps1)`); return; }
  const key = fs.readFileSync(KEY_FILE, 'utf8').trim();
  const out = fs.openSync(path.join(STATE, 'tunnel.log'), 'a');
  const args = ['run', '--config', PROFILE];
  const bridgeKey = path.join(STATE, 'bridge-key');
  // tunnel-client adds this header to every request it forwards; server.mjs refuses requests without it
  if (fs.existsSync(bridgeKey)) args.push('--mcp.extra-headers', `X-Bridge-Key: file:${bridgeKey.replace(/\\/g, '/')}`);
  const started = Date.now();
  let restarted = false;
  const again = (why) => {
    if (restarted) return; restarted = true;
    try { fs.closeSync(out); } catch {}
    const ranFor = Date.now() - started;
    const next = ranFor > 60_000 ? 0 : attempt + 1;
    const delay = Math.min(60_000, 2_000 * 2 ** Math.min(next, 5));
    log(`tunnel-client ${why} after ${Math.round(ranFor / 1000)}s; restarting in ${delay / 1000}s`);
    setTimeout(() => runTunnel(next), delay);
  };
  child = spawn(EXE, args, { cwd: path.dirname(EXE), windowsHide: true, stdio: ['ignore', out, out], env: { ...process.env, CONTROL_PLANE_API_KEY: key } });
  log(`tunnel-client started pid ${child.pid} (config ${PROFILE})`);
  // 'error' fires instead of 'exit' when Windows refuses to start the exe (antivirus, blocked file)
  child.on('error', (e) => again(`could not start (${e.message}; check that antivirus did not block tunnel\\tunnel-client.exe)`));
  child.on('close', (code, sig) => again(`exited code=${code} sig=${sig}`));
}
runTunnel();
