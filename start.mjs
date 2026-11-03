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

await startHttp();
log('chatgpt-windows-bridge server listening on 127.0.0.1 (see server.mjs for port)');

function runTunnel(attempt = 0) {
  const missing = [EXE, KEY_FILE, PROFILE].find((f) => !fs.existsSync(f));
  if (missing) { log(`tunnel not started: missing ${missing}`); return; }
  const key = fs.readFileSync(KEY_FILE, 'utf8').trim();
  const out = fs.openSync(path.join(STATE, 'tunnel.log'), 'a');
  const args = ['run', '--config', PROFILE];
  const bridgeKey = path.join(STATE, 'bridge-key');
  // tunnel-client adds this header to every request it forwards; server.mjs refuses requests without it
  if (fs.existsSync(bridgeKey)) args.push('--mcp.extra-headers', `X-Bridge-Key: file:${bridgeKey.replace(/\\/g, '/')}`);
  const child = spawn(EXE, args, { cwd: path.dirname(EXE), windowsHide: true, stdio: ['ignore', out, out], env: { ...process.env, CONTROL_PLANE_API_KEY: key } });
  const started = Date.now();
  log(`tunnel-client started pid ${child.pid} (config ${PROFILE})`);
  child.on('exit', (code, sig) => {
    fs.closeSync(out);
    const ranFor = Date.now() - started;
    const next = ranFor > 60_000 ? 0 : attempt + 1;
    const delay = Math.min(60_000, 2_000 * 2 ** Math.min(next, 5));
    log(`tunnel-client exited code=${code} sig=${sig} after ${Math.round(ranFor / 1000)}s; restarting in ${delay / 1000}s`);
    setTimeout(() => runTunnel(next), delay);
  });
  const stop = () => { try { child.kill(); } catch {} process.exit(0); };
  process.once('SIGINT', stop);
  process.once('SIGTERM', stop);
}
runTunnel();
