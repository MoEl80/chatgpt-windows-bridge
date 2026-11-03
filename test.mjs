// End-to-end test: real MCP client -> server on a test port. Usage:
//   node test.mjs                 (starts its own servers on free ports with temporary secrets)
//   node test.mjs <full-mcp-url>  (tests an already-running/public server)
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';
import { Client } from '@modelcontextprotocol/sdk/client/index.js';
import { StreamableHTTPClientTransport } from '@modelcontextprotocol/sdk/client/streamableHttp.js';

const HERE = path.dirname(fileURLToPath(import.meta.url));
setTimeout(() => { console.error('FAIL: test timed out after 120 s'); process.exit(2); }, 120_000).unref();
let url = process.argv[2];
let httpServer;
if (!url) {
  const { startHttp, toWinPath, insideRoots, loadConfig, readConfigFile, isBridgeSecret } = await import('./server.mjs');
  // settings written by Windows PowerShell 5.1 may start with a byte-order mark
  const bomFile = path.join(os.tmpdir(), `cgb-bom-${Date.now()}.json`);
  fs.writeFileSync(bomFile, '\uFEFF{"mode":"read"}');
  assert.equal(readConfigFile(bomFile).mode, 'read'); fs.rmSync(bomFile);
  // the default folder moves inside the allowed folders
  assert.equal(loadConfig({ roots: ['C:\\Work'], cwd: 'C:\\Users\\x' }).cwd, 'C:\\Work');
  assert.ok(isBridgeSecret(path.join(HERE, '.state', 'token')));
  console.log('PASS BOM settings file, default folder inside roots, own secrets recognised');
  assert.equal(toWinPath('/c/Work/x y/z.md'), 'C:\\Work\\x y\\z.md');
  assert.equal(toWinPath('rel\\a.txt', 'C:\\Work'), 'C:\\Work\\rel\\a.txt');
  assert.ok(insideRoots('C:\\Work\\a.txt', ['C:\\Work']) && !insideRoots('C:\\Workshop\\a.txt', ['C:\\Work']) && insideRoots('D:\\x', []));
  const token = crypto.randomBytes(32).toString('base64url');
  const bridgeKey = crypto.randomBytes(32).toString('base64url');
  httpServer = await startHttp({ port: 0, token, bridgeKey, config: loadConfig({ mode: 'full', roots: [], cwd: os.tmpdir() }) });
  const base = `http://127.0.0.1:${httpServer.address().port}`;
  // the right path without the bridge key must be refused
  assert.equal((await fetch(`${base}/${token}/mcp`, { method: 'POST' })).status, 401);
  assert.equal((await fetch(`${base}/${token}/mcp`, { method: 'POST', headers: { 'x-bridge-key': 'wrong' } })).status, 401);
  globalThis.__headers = { 'x-bridge-key': bridgeKey };
  url = `${base}/${token}/mcp`;
  // wrong path must 404, health must be ok
  assert.equal((await fetch(`${base}/wrong/mcp`, { method: 'POST' })).status, 404);
  assert.equal((await fetch(`${base}/healthz`)).status, 200);
}

const client = new Client({ name: 'cgb-test', version: '1' });
await client.connect(new StreamableHTTPClientTransport(new URL(url), { requestInit: { headers: globalThis.__headers || {} } }));
console.log('PASS secret path + bridge key: wrong path 404, missing/wrong key 401');
const text = (r) => r.content.map((c) => c.text).join('');
const call = async (name, args) => client.callTool({ name, arguments: args });

const tools = (await client.listTools()).tools.map((t) => t.name).sort();
assert.deepEqual(tools, ['edit_file', 'job_output', 'job_stop', 'list_dir', 'read_file', 'run', 'write_file']);
console.log('PASS tools/list:', tools.join(','));

let r = await call('run', { command: 'hostname && echo "dollar:$((1+2))"' });
assert.match(text(r), /exit_code: 0/); assert.match(text(r), /dollar:3/);
console.log('PASS bash:', text(r).split('\n').slice(-3).join(' | '));

r = await call('run', { shell: 'powershell', command: '$PSVersionTable.PSVersion.Major; "uni:\u00e9\u0634"' });
assert.match(text(r), /exit_code: 0/); assert.match(text(r), /uni:\u00e9\u0634/);
console.log('PASS powershell + utf8');

r = await call('run', { command: 'exit 7' });
assert.match(text(r), /exit_code: 7/);
console.log('PASS exit code');

const auditMarker = `audit-secret-${crypto.randomBytes(6).toString('hex')}`;
r = await call('run', { command: `echo ${auditMarker}` });
assert.match(text(r), new RegExp(auditMarker));
await new Promise((resolve) => setTimeout(resolve, 100));
if (httpServer) {
  const callsLog = fs.readFileSync(path.join(HERE, '.state', 'calls.log'), 'utf8');
  assert.ok(!callsLog.includes(auditMarker), 'calls.log must not persist raw shell command text');
  console.log('PASS audit log stores command fingerprint, not raw command text');
}

const dir = path.join(os.tmpdir(), `cgb test éش 'q' ${Date.now()}`);
fs.mkdirSync(dir);
const f = path.join(dir, 'a b.txt');
r = await call('write_file', { path: f, content: 'line1\r\nline2\r\n' });
assert.match(text(r), /sha256: /);
r = await call('read_file', { path: f });
const sha = /sha256: (\w+)/.exec(text(r))[1];
r = await call('edit_file', { path: f, old_string: 'line1\nline2', new_string: 'one\ntwo', expected_sha256: sha });
assert.ok(!r.isError, text(r));
assert.equal(fs.readFileSync(f, 'utf8'), 'one\r\ntwo\r\n');
r = await call('write_file', { path: f, content: 'x', expected_sha256: sha });
assert.ok(r.isError && /changed since/.test(text(r)), 'stale sha must be refused');
const bin = crypto.randomBytes(70000);
r = await call('write_file', { path: path.join(dir, 'b.bin'), content: bin.toString('base64'), encoding: 'base64' });
r = await call('read_file', { path: path.join(dir, 'b.bin'), encoding: 'base64' });
assert.ok(Buffer.from(text(r).split('--- base64 ---\n')[1], 'base64').equals(bin));
r = await call('list_dir', { path: dir });
assert.match(text(r), /f a b\.txt/);
console.log('PASS Unicode/space path + write/read/edit (CRLF) / stale-sha refusal / 70000-byte binary roundtrip / list_dir');
if (httpServer) {
  const own = path.join(HERE, '.state', 'token');
  r = await call('read_file', { path: own });
  assert.ok(r.isError && /secret files/.test(text(r)), 'own secrets must be refused by direct file tools: ' + text(r));
  console.log('PASS direct file tool refuses the bridge .state secrets');
}

r = await call('run', { command: 'echo start; sleep 4; echo end', wait_sec: 1 });
assert.match(text(r), /STILL RUNNING/);
const job = /job_id: (\w+)/.exec(text(r))[1];
r = await call('job_output', { job_id: job, wait_sec: 20 });
assert.match(text(r), /exit_code: 0/); assert.match(text(r), /end/);
console.log('PASS background job + job_output');

fs.rmSync(dir, { recursive: true, force: true });
await client.close();
if (httpServer) {
  const { startHttp, loadConfig } = await import('./server.mjs');
  // read-only mode: only read tools are offered
  const t2 = crypto.randomBytes(32).toString('base64url');
  const ro = await startHttp({ port: 0, token: t2, bridgeKey: null, config: loadConfig({ mode: 'read', roots: [], cwd: os.tmpdir() }) });
  const c2 = new Client({ name: 'cgb-test-ro', version: '1' });
  await c2.connect(new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${ro.address().port}/${t2}/mcp`)));
  assert.deepEqual((await c2.listTools()).tools.map((t) => t.name).sort(), ['list_dir', 'read_file']);
  await c2.close(); ro.close();
  console.log('PASS read-only mode offers only read_file + list_dir');

  // allowed folders: lexical outside paths and junction/reparse escapes are refused
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'cgb-root-'));
  const t3 = crypto.randomBytes(32).toString('base64url');
  const rs = await startHttp({ port: 0, token: t3, bridgeKey: null, config: loadConfig({ mode: 'full', roots: [root], cwd: root }) });
  const c3 = new Client({ name: 'cgb-test-roots', version: '1' });
  await c3.connect(new StreamableHTTPClientTransport(new URL(`http://127.0.0.1:${rs.address().port}/${t3}/mcp`)));
  let x = await c3.callTool({ name: 'write_file', arguments: { path: path.join(root, 'ok.txt'), content: 'ok' } });
  assert.ok(!x.isError, text(x));
  x = await c3.callTool({ name: 'read_file', arguments: { path: path.join(os.tmpdir(), 'outside.txt') } });
  assert.ok(x.isError && /outside the allowed folders/.test(text(x)), 'outside path must be refused');
  x = await c3.callTool({ name: 'run', arguments: { command: 'echo hi', cwd: os.homedir() } });
  assert.ok(x.isError && /outside the allowed folders/.test(text(x)), 'outside cwd must be refused');

  if (process.platform === 'win32') {
    const outside = fs.mkdtempSync(path.join(os.tmpdir(), 'cgb-outside-'));
    fs.writeFileSync(path.join(outside, 'secret.txt'), 'outside');
    const junction = path.join(root, 'escape-junction');
    try {
      fs.symlinkSync(outside, junction, 'junction');
      x = await c3.callTool({ name: 'read_file', arguments: { path: path.join(junction, 'secret.txt') } });
      assert.ok(x.isError && /junction|reparse point|outside the allowed/.test(text(x)), 'junction escape must be refused: ' + text(x));
      console.log('PASS allowed roots refuse NTFS junction escape');
    } catch (e) {
      if (e?.code === 'EPERM' || e?.code === 'EACCES') console.log('SKIP junction creation not permitted on this Windows configuration');
      else throw e;
    } finally { fs.rmSync(outside, { recursive: true, force: true }); }
  }

  await c3.close(); rs.close(); fs.rmSync(root, { recursive: true, force: true });
  console.log('PASS allowed folders refuse outside paths and cwd');
}

httpServer?.close();
console.log('ALL PASS');
process.exit(0);
