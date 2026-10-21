#!/usr/bin/env node
// agent-reach-browser —— 无头采集浏览器
//
// 让 OpenCLI 类渠道（抖音 / 小红书 / B站 / Twitter / Reddit / 雪球 / 快手）不再借用你的日常 Chrome：
// 一个独立的 Chromium（独立账号目录 + OpenCLI 扩展）在后台无头常驻，并设为 OpenCLI 默认 profile。
// 所有 `opencli <站点> ...` 命令原样不改，自动走它；登录失效时 `login` 弹一次窗口，关掉即回无头。
//
// 用法：agent-reach-browser <命令>
//   setup [--proxy URL] [--profile-dir DIR] [--chrome PATH] [--alias NAME]   一次性安装（可重复跑）
//   status | start | stop | restart
//   login [URL...]          弹出有窗口版本，登录 / 过验证后关窗口，自动回到无头
//   cookies <域名> [--json|--netscape]  导出该域名 Cookie（默认 "k=v; k=v"；--netscape 给 yt-dlp 用）
//   sync-xueqiu             把雪球登录同步给 agent-reach（雪球 API 渠道用）
//   uninstall               移除后台服务（账号目录保留）
//   run                     后台服务入口，不要手动调

import { spawn, spawnSync, execFileSync } from 'node:child_process';
import { createRequire } from 'node:module';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const HOME = os.homedir();
const PLATFORM = process.platform;
const AR_DIR = path.join(HOME, '.agent-reach');
const CONFIG_PATH = path.join(AR_DIR, 'browser.json');
const SELF = path.resolve(process.argv[1]);
const SERVICE = 'agent-reach-browser';
const LAUNCHD_LABEL = 'com.agent-reach.browser';

// 走代理的海外域名（国内站一律直连，避免抖音/小红书/B站因海外出口触发风控）。
// Google / reCAPTCHA 系必须在内：Reddit、X 的登录页依赖它，直连被挡会报「请禁用扩展或换浏览器」。
const DEFAULT_PROXY_DOMAINS = [
  'x.com', 'twitter.com', 'twimg.com', 't.co',
  'reddit.com', 'redd.it', 'redditmedia.com', 'redditstatic.com',
  'youtube.com', 'ytimg.com', 'googlevideo.com',
  'google.com', 'gstatic.com', 'googleapis.com', 'googleusercontent.com', 'recaptcha.net',
  'hcaptcha.com', 'arkoselabs.com', 'linkedin.com', 'licdn.com',
];

const DEFAULTS = {
  chrome: '',
  profileDir: path.join(AR_DIR, 'browser-profile'),
  extensionDir: path.join(AR_DIR, 'browser-extension'),
  cdpPort: 19229,
  proxy: '',
  proxyDomains: DEFAULT_PROXY_DOMAINS,
  alias: 'agent-reach',
  contextId: '',
};

// ───────── 基础工具 ─────────

const log = (...a) => console.log(...a);
const die = (msg) => { console.error(`❌ ${msg}`); process.exit(1); };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function loadConfig() {
  let saved = {};
  try { saved = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')); } catch { /* 首次运行 */ }
  return { ...DEFAULTS, ...saved };
}

function saveConfig(cfg) {
  fs.mkdirSync(AR_DIR, { recursive: true });
  const { proxyDomains, ...rest } = cfg;
  const out = { ...rest };
  // 只有用户改过域名列表才落盘，否则以后升级能吃到新的默认列表
  if (JSON.stringify(proxyDomains) !== JSON.stringify(DEFAULT_PROXY_DOMAINS)) out.proxyDomains = proxyDomains;
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(out, null, 2) + '\n');
}

function parseFlags(args) {
  const flags = {}; const rest = [];
  for (let i = 0; i < args.length; i++) {
    const a = args[i];
    if (a.startsWith('--')) {
      const key = a.slice(2);
      const next = args[i + 1];
      if (next === undefined || next.startsWith('--')) flags[key] = true; else { flags[key] = next; i++; }
    } else rest.push(a);
  }
  return { flags, rest };
}

function which(cmd) {
  const r = spawnSync(PLATFORM === 'win32' ? 'where' : 'which', [cmd], { encoding: 'utf8' });
  return r.status === 0 ? r.stdout.split(/\r?\n/)[0].trim() : '';
}

function opencli(args, opts = {}) {
  const bin = which('opencli') || die('找不到 opencli，先跑 agent-reach install 装好 OpenCLI');
  // Windows 上 opencli 是 .cmd，需要 shell
  return spawnSync(bin, args, { encoding: 'utf8', shell: PLATFORM === 'win32', timeout: 60000, ...opts });
}

function opencliVersion() {
  const r = opencli(['--version']);
  const m = `${r.stdout}`.match(/(\d+\.\d+\.\d+)/);
  return m ? m[1] : '';
}

// ───────── 浏览器可执行文件 ─────────

function playwrightCacheDir() {
  if (process.env.PLAYWRIGHT_BROWSERS_PATH) return process.env.PLAYWRIGHT_BROWSERS_PATH;
  if (PLATFORM === 'darwin') return path.join(HOME, 'Library', 'Caches', 'ms-playwright');
  if (PLATFORM === 'win32') return path.join(process.env.LOCALAPPDATA || path.join(HOME, 'AppData', 'Local'), 'ms-playwright');
  return path.join(HOME, '.cache', 'ms-playwright');
}

function findPlaywrightChromium() {
  const base = playwrightCacheDir();
  let dirs = [];
  try { dirs = fs.readdirSync(base).filter((d) => /^chromium-\d+$/.test(d)); } catch { return ''; }
  // 新版本优先
  dirs.sort((a, b) => Number(b.split('-')[1]) - Number(a.split('-')[1]));
  const rel = {
    darwin: [
      ['chrome-mac-arm64', 'Google Chrome for Testing.app', 'Contents', 'MacOS', 'Google Chrome for Testing'],
      ['chrome-mac', 'Google Chrome for Testing.app', 'Contents', 'MacOS', 'Google Chrome for Testing'],
      ['chrome-mac', 'Chromium.app', 'Contents', 'MacOS', 'Chromium'],
    ],
    linux: [['chrome-linux', 'chrome'], ['chrome-linux64', 'chrome']],
    win32: [['chrome-win', 'chrome.exe'], ['chrome-win64', 'chrome.exe']],
  }[PLATFORM] || [];
  for (const d of dirs) for (const r of rel) {
    const p = path.join(base, d, ...r);
    if (fs.existsSync(p)) return p;
  }
  return '';
}

function ensureChrome(cfg) {
  if (cfg.chrome && fs.existsSync(cfg.chrome)) return cfg.chrome;
  let found = findPlaywrightChromium();
  if (!found) {
    // 正式版 Google Chrome 137+ 禁止命令行加载扩展，只能用 Chromium / Chrome for Testing
    log('• 下载 Chromium（Playwright 提供，约 150MB，只需一次）…');
    const npx = which('npx') || die('找不到 npx（需要 Node.js）');
    const r = spawnSync(npx, ['-y', 'playwright@latest', 'install', 'chromium'], { stdio: 'inherit', shell: PLATFORM === 'win32' });
    if (r.status !== 0) die('Chromium 下载失败。可手动跑：npx playwright install chromium，或 --chrome 指定一个 Chromium 路径');
    found = findPlaywrightChromium();
  }
  if (!found) die('没找到可用的 Chromium。用 --chrome <路径> 指定一个 Chromium / Chrome for Testing（正式版 Chrome 不行）');
  return found;
}

function chromeMajor(chrome) {
  try {
    const out = execFileSync(chrome, ['--version'], { encoding: 'utf8', timeout: 15000 });
    return (out.match(/(\d+)\.\d+\.\d+\.\d+/) || [])[1] || '';
  } catch { return ''; }
}

// 无头模式的 UA 带 "HeadlessChrome"，抖音会直接给验证码页（实测）。换成同版本的普通 Chrome UA。
function normalUA(major) {
  const plat = {
    darwin: 'Macintosh; Intel Mac OS X 10_15_7',
    win32: 'Windows NT 10.0; Win64; x64',
  }[PLATFORM] || 'X11; Linux x86_64';
  return `Mozilla/5.0 (${plat}) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/${major || '140'}.0.0.0 Safari/537.36`;
}

// ───────── OpenCLI 扩展 ─────────

async function ensureExtension(cfg, { force = false } = {}) {
  const manifest = path.join(cfg.extensionDir, 'manifest.json');
  if (!force && fs.existsSync(manifest)) return;
  const ver = opencliVersion();
  // 扩展随 OpenCLI 每个 release 发布；优先取和本机 OpenCLI 同版本的，取不到用最新
  const apis = [
    ver && `https://api.github.com/repos/jackwener/opencli/releases/tags/v${ver}`,
    'https://api.github.com/repos/jackwener/opencli/releases/latest',
  ].filter(Boolean);
  let url = '';
  for (const api of apis) {
    try {
      const res = await fetch(api, { headers: { 'User-Agent': 'agent-reach-browser' } });
      if (!res.ok) continue;
      const asset = (await res.json()).assets?.find((a) => /opencli-extension.*\.zip$/.test(a.name));
      if (asset) { url = asset.browser_download_url; break; }
    } catch { /* 换下一个 */ }
  }
  if (!url) die('没拿到 OpenCLI 扩展下载地址（GitHub 不通？可设 HTTPS_PROXY 后重试）');
  log(`• 下载 OpenCLI 扩展：${path.basename(url)}`);
  const res = await fetch(url);
  if (!res.ok) die(`扩展下载失败：HTTP ${res.status}`);
  const zip = path.join(os.tmpdir(), `opencli-extension-${process.pid}.zip`);
  fs.writeFileSync(zip, Buffer.from(await res.arrayBuffer()));
  fs.rmSync(cfg.extensionDir, { recursive: true, force: true });
  fs.mkdirSync(cfg.extensionDir, { recursive: true });
  const unzip = PLATFORM === 'win32'
    ? spawnSync('powershell', ['-NoProfile', '-Command', `Expand-Archive -Force -Path '${zip}' -DestinationPath '${cfg.extensionDir}'`])
    : spawnSync('unzip', ['-o', '-q', zip, '-d', cfg.extensionDir]);
  fs.rmSync(zip, { force: true });
  if (unzip.status !== 0) die('扩展解压失败（需要 unzip）');
  // 有的包多套一层目录，把 manifest 所在目录提上来
  if (!fs.existsSync(manifest)) {
    const inner = fs.readdirSync(cfg.extensionDir).map((d) => path.join(cfg.extensionDir, d))
      .find((d) => fs.existsSync(path.join(d, 'manifest.json')));
    if (!inner) die('扩展包里没找到 manifest.json');
    for (const f of fs.readdirSync(inner)) fs.renameSync(path.join(inner, f), path.join(cfg.extensionDir, f));
    fs.rmdirSync(inner);
  }
}

// ───────── 启动参数 ─────────

function pacScript(cfg) {
  const host = cfg.proxy.replace(/^\w+:\/\//, '').replace(/\/.*$/, '');
  const kind = /^socks/i.test(cfg.proxy) ? 'SOCKS5' : 'PROXY';
  return `function FindProxyForURL(url, host) {
  var d = ${JSON.stringify(cfg.proxyDomains)};
  for (var i = 0; i < d.length; i++) if (host === d[i] || dnsDomainIs(host, '.' + d[i])) return '${kind} ${host}';
  return 'DIRECT';
}`;
}

function browserArgs(cfg, { headless }) {
  const args = [
    `--user-data-dir=${cfg.profileDir}`,
    `--load-extension=${cfg.extensionDir}`,
    `--disable-extensions-except=${cfg.extensionDir}`,
    '--disable-blink-features=AutomationControlled',
    `--remote-debugging-port=${cfg.cdpPort}`,
    '--remote-debugging-address=127.0.0.1',
    '--no-first-run', '--no-default-browser-check', '--window-size=1440,900',
  ];
  // file:// 的 PAC 会被忽略（实测），必须内嵌成 data: URL
  if (cfg.proxy) args.push(`--proxy-pac-url=data:application/x-ns-proxy-autoconfig;base64,${Buffer.from(pacScript(cfg)).toString('base64')}`);
  if (headless) args.unshift('--headless=new', `--user-agent=${normalUA(chromeMajor(cfg.chrome))}`);
  return args;
}

// ───────── 进程状态 ─────────

async function cdpUp(cfg) {
  try { return (await fetch(`http://127.0.0.1:${cfg.cdpPort}/json/version`, { signal: AbortSignal.timeout(1500) })).ok; } catch { return false; }
}

// 匹配串以 -- 开头，pgrep/pkill 必须先给 -- 结束选项解析，否则永远匹配不到
function isRunning(cfg) {
  if (PLATFORM === 'win32') {
    const r = spawnSync('wmic', ['process', 'where', "name='chrome.exe'", 'get', 'CommandLine'], { encoding: 'utf8' });
    return `${r.stdout}`.includes(cfg.profileDir);
  }
  return spawnSync('pgrep', ['-f', '--', `--user-data-dir=${cfg.profileDir}`]).status === 0;
}

function killBrowser(cfg) {
  if (PLATFORM === 'win32') {
    spawnSync('powershell', ['-NoProfile', '-Command',
      `Get-CimInstance Win32_Process -Filter "name='chrome.exe'" | Where-Object { $_.CommandLine -like '*${cfg.profileDir}*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }`]);
  } else spawnSync('pkill', ['-f', '--', `--user-data-dir=${cfg.profileDir}`]);
}

async function waitStopped(cfg) {
  for (let i = 0; i < 40; i++) { if (!isRunning(cfg)) return; await sleep(250); }
  killBrowser(cfg); await sleep(1000);
}

// OpenCLI 把每个连上的浏览器记成一个 contextId；`profile list` 每行形如 "  dvqqh8c4 alias default — connected v1.0.26"
function profileList() {
  const out = `${opencli(['profile', 'list']).stdout}`;
  return out.split('\n').map((l) => l.trim().match(/^([a-z0-9]{6,})\b(.*)$/)).filter(Boolean)
    .map(([, id, tail]) => ({ id, connected: /connected/.test(tail) && !/disconnected/.test(tail), line: tail }));
}

// ───────── 后台服务 ─────────

const nodeBin = process.execPath;
const launchdPlist = path.join(HOME, 'Library', 'LaunchAgents', `${LAUNCHD_LABEL}.plist`);
const systemdUnit = path.join(HOME, '.config', 'systemd', 'user', `${SERVICE}.service`);
const uid = () => (os.userInfo().uid);

function installService() {
  const logFile = path.join(AR_DIR, 'browser.log');
  if (PLATFORM === 'darwin') {
    fs.mkdirSync(path.dirname(launchdPlist), { recursive: true });
    fs.writeFileSync(launchdPlist, `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LAUNCHD_LABEL}</string>
  <key>ProgramArguments</key><array><string>${nodeBin}</string><string>${SELF}</string><string>run</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>ProcessType</key><string>Background</string>
  <key>StandardOutPath</key><string>${logFile}</string>
  <key>StandardErrorPath</key><string>${logFile}</string>
</dict>
</plist>
`);
  } else if (PLATFORM === 'linux') {
    fs.mkdirSync(path.dirname(systemdUnit), { recursive: true });
    fs.writeFileSync(systemdUnit, `[Unit]
Description=agent-reach headless browser (OpenCLI collector)
After=network-online.target

[Service]
ExecStart=${nodeBin} ${SELF} run
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
`);
    spawnSync('systemctl', ['--user', 'daemon-reload']);
    spawnSync('systemctl', ['--user', 'enable', SERVICE]);
  } else if (PLATFORM === 'win32') {
    spawnSync('schtasks', ['/Create', '/F', '/TN', SERVICE, '/SC', 'ONLOGON', '/RL', 'LIMITED',
      '/TR', `"${nodeBin}" "${SELF}" run`]);
  }
}

function serviceStart() {
  if (PLATFORM === 'darwin') {
    const target = `gui/${uid()}/${LAUNCHD_LABEL}`;
    if (spawnSync('launchctl', ['print', target]).status === 0) spawnSync('launchctl', ['kickstart', target]);
    else spawnSync('launchctl', ['bootstrap', `gui/${uid()}`, launchdPlist]);
  } else if (PLATFORM === 'linux') {
    spawnSync('systemctl', ['--user', 'start', SERVICE]);
  } else if (PLATFORM === 'win32') {
    spawnSync('schtasks', ['/Run', '/TN', SERVICE]);
  }
}

function serviceStop() {
  if (PLATFORM === 'darwin') spawnSync('launchctl', ['bootout', `gui/${uid()}/${LAUNCHD_LABEL}`]);
  else if (PLATFORM === 'linux') spawnSync('systemctl', ['--user', 'stop', SERVICE]);
  else if (PLATFORM === 'win32') spawnSync('schtasks', ['/End', '/TN', SERVICE]);
}

function serviceRemove() {
  serviceStop();
  if (PLATFORM === 'darwin') fs.rmSync(launchdPlist, { force: true });
  else if (PLATFORM === 'linux') { spawnSync('systemctl', ['--user', 'disable', SERVICE]); fs.rmSync(systemdUnit, { force: true }); }
  else if (PLATFORM === 'win32') spawnSync('schtasks', ['/Delete', '/F', '/TN', SERVICE]);
}

// ───────── 命令 ─────────

async function cmdStart(cfg) {
  serviceStart();
  for (let i = 0; i < 60 && !(await cdpUp(cfg)); i++) await sleep(250);
  // 扩展连上 OpenCLI daemon 需要几秒
  for (let i = 0; i < 40; i++) {
    if (cfg.contextId && profileList().some((p) => p.id === cfg.contextId && p.connected)) break;
    await sleep(500);
  }
  await cmdStatus(cfg);
}

async function cmdStop(cfg) {
  serviceStop();
  await waitStopped(cfg);
  log('已停止');
}

async function cmdStatus(cfg) {
  const running = isRunning(cfg);
  log(`浏览器：${running ? '运行中' : '未运行'}（账号目录 ${cfg.profileDir}）`);
  const me = cfg.contextId && profileList().find((p) => p.id === cfg.contextId);
  log(`OpenCLI：${me ? `${me.id}${me.line}` : '未连接（跑 agent-reach-browser restart；仍不行看 ~/.agent-reach/browser.log）'}`);
  log(`代理：${cfg.proxy ? `${cfg.proxy}（仅 ${cfg.proxyDomains.length} 个海外域名走代理）` : '无'}`);
}

async function cmdRun(cfg) {
  if (!cfg.chrome) die('未 setup，先跑 agent-reach-browser setup');
  const child = spawn(cfg.chrome, [...browserArgs(cfg, { headless: true }), 'about:blank'], { stdio: 'inherit' });
  const forward = (sig) => () => child.kill(sig);
  process.on('SIGTERM', forward('SIGTERM')); process.on('SIGINT', forward('SIGINT'));
  child.on('exit', (code) => process.exit(code ?? 1));
}

async function cmdLogin(cfg, urls) {
  if (PLATFORM === 'linux' && !process.env.DISPLAY && !process.env.WAYLAND_DISPLAY) {
    die('这台 Linux 没有图形界面，没法弹登录窗口。请在有桌面的机器上登录后，把账号目录拷过来');
  }
  serviceStop();
  await waitStopped(cfg);
  log('已弹出专用浏览器窗口。登录 / 过完验证后直接关掉这个窗口，会自动回到无头模式。');
  spawnSync(cfg.chrome, [...browserArgs(cfg, { headless: false }), ...(urls.length ? urls : ['about:blank'])], { stdio: 'ignore' });
  log('窗口已关闭，恢复无头常驻…');
  await cmdStart(cfg);
}

async function getCookies(cfg) {
  if (!(await cdpUp(cfg))) die('浏览器没在跑，先 agent-reach-browser start');
  const { webSocketDebuggerUrl } = await (await fetch(`http://127.0.0.1:${cfg.cdpPort}/json/version`)).json();
  // Node 22+ 自带 WebSocket；更老的版本借 OpenCLI 自带的 ws
  let WS = globalThis.WebSocket;
  if (!WS) {
    const root = execFileSync(which('npm') || 'npm', ['root', '-g'], { encoding: 'utf8', shell: PLATFORM === 'win32' }).trim();
    WS = createRequire(path.join(root, '@jackwener', 'opencli', 'package.json'))('ws');
  }
  const ws = new WS(webSocketDebuggerUrl);
  await new Promise((resolve, reject) => { ws.onopen = resolve; ws.onerror = reject; });
  const result = await new Promise((resolve) => {
    ws.onmessage = (e) => { const d = JSON.parse(e.data); if (d.id === 1) resolve(d.result); };
    ws.send(JSON.stringify({ id: 1, method: 'Storage.getCookies' }));
  });
  ws.close();
  return result.cookies;
}

// 三种格式：默认 "k=v; k=v"（HTTP 头 / agent-reach 配置）、--json（CDP 原样）、
// --netscape（cookies.txt，给 yt-dlp --cookies / curl -b 用）
async function cmdCookies(cfg, domain, format) {
  if (!domain) die('用法：agent-reach-browser cookies <域名> [--json | --netscape]');
  const d = domain.replace(/^\./, '');
  const list = (await getCookies(cfg)).filter((c) => c.domain.replace(/^\./, '').endsWith(d));
  if (format === 'json') return process.stdout.write(JSON.stringify(list, null, 2) + '\n');
  if (format === 'netscape') {
    const lines = list.map((c) => [c.domain, c.domain.startsWith('.') ? 'TRUE' : 'FALSE', c.path,
      c.secure ? 'TRUE' : 'FALSE', c.session || c.expires < 0 ? 0 : Math.floor(c.expires), c.name, c.value].join('\t'));
    return process.stdout.write(['# Netscape HTTP Cookie File', ...lines].join('\n') + '\n');
  }
  process.stdout.write(list.map((c) => `${c.name}=${c.value}`).join('; ') + '\n');
}

async function cmdSyncXueqiu(cfg) {
  const list = (await getCookies(cfg)).filter((c) => c.domain.replace(/^\./, '').endsWith('xueqiu.com'));
  if (!list.some((c) => c.name === 'xq_a_token')) die('专用浏览器里雪球没登录，先 agent-reach-browser login https://xueqiu.com');
  const header = list.map((c) => `${c.name}=${c.value}`).join('; ');
  const base = spawnSync('pipx', ['environment', '--value', 'PIPX_LOCAL_VENVS'], { encoding: 'utf8', shell: PLATFORM === 'win32' }).stdout?.trim()
    || path.join(HOME, '.local', 'pipx', 'venvs');
  const py = path.join(base, 'agent-reach', PLATFORM === 'win32' ? 'Scripts\\python.exe' : 'bin/python');
  if (!fs.existsSync(py)) die(`找不到 agent-reach 的 python：${py}`);
  const r = spawnSync(py, ['-c', "import os;from agent_reach.config import Config;Config().set('xueqiu_cookie',os.environ['XQ_COOKIE'])"],
    { env: { ...process.env, XQ_COOKIE: header }, encoding: 'utf8' });
  if (r.status !== 0) die(`写入失败：${r.stderr}`);
  log('✅ 已同步雪球登录到 agent-reach（agent-reach doctor 里雪球应为 ok）');
}

async function cmdSetup(cfg, flags) {
  if (flags['profile-dir']) cfg.profileDir = path.resolve(String(flags['profile-dir']).replace(/^~/, HOME));
  if (flags.chrome) cfg.chrome = String(flags.chrome);
  if (flags.alias) cfg.alias = String(flags.alias);
  if (flags.proxy !== undefined) cfg.proxy = flags.proxy === true ? '' : String(flags.proxy);
  if (flags['cdp-port']) cfg.cdpPort = Number(flags['cdp-port']);

  log('▶ 1/4 准备 Chromium');
  cfg.chrome = ensureChrome(cfg);
  log(`  ✅ ${cfg.chrome}`);

  log('▶ 2/4 准备 OpenCLI 扩展');
  await ensureExtension(cfg, { force: Boolean(flags['update-extension']) });
  log(`  ✅ ${cfg.extensionDir}`);

  log('▶ 3/4 注册后台服务并启动');
  fs.mkdirSync(cfg.profileDir, { recursive: true });
  saveConfig(cfg);
  installService();
  const before = new Set(profileList().map((p) => p.id));
  serviceStop(); await waitStopped(cfg);
  serviceStart();
  for (let i = 0; i < 60 && !(await cdpUp(cfg)); i++) await sleep(250);
  if (!(await cdpUp(cfg))) die('浏览器没起来，看 ~/.agent-reach/browser.log');

  log('▶ 4/4 接入 OpenCLI');
  // contextId 存在扩展自己的存储里（跟账号目录走），已知就复用；否则找新冒出来的那个
  let id = '';
  for (let i = 0; i < 40 && !id; i++) {
    const conn = profileList().filter((p) => p.connected);
    id = (cfg.contextId && conn.find((p) => p.id === cfg.contextId)?.id) || conn.find((p) => !before.has(p.id))?.id || '';
    if (!id) await sleep(500);
  }
  if (!id) die('OpenCLI 没看到这个浏览器连上。先跑一次 opencli doctor 拉起 daemon，再重跑 setup');
  cfg.contextId = id;
  saveConfig(cfg);
  opencli(['profile', 'rename', id, cfg.alias]);
  opencli(['profile', 'use', cfg.alias]);
  log(`  ✅ OpenCLI 默认 profile → ${cfg.alias}（${id}）`);

  log(`
✅ 完成。之后所有 opencli 命令默认走这个无头浏览器，不再碰你的日常 Chrome。
下一步：在它里面登录要用的平台（扫码 / 账号密码，关掉窗口自动回无头）：
  agent-reach-browser login https://www.douyin.com https://www.xiaohongshu.com https://passport.bilibili.com/login
雪球 API 渠道：登录 xueqiu.com 后再跑 agent-reach-browser sync-xueqiu`);
}

async function cmdUninstall(cfg) {
  serviceRemove();
  await waitStopped(cfg);
  log(`已移除后台服务。账号目录保留在 ${cfg.profileDir}（要彻底清掉自己删）。
OpenCLI 默认 profile 仍指向 ${cfg.alias}，改回日常 Chrome：opencli profile list 后 opencli profile use <那个 id>`);
}

// ───────── 入口 ─────────

const [cmd = 'status', ...argv] = process.argv.slice(2);
const { flags, rest } = parseFlags(argv);
const cfg = loadConfig();
// run 是 setup 过程中就会被服务拉起的入口，那时 contextId 还没写入，不能拦
const needSetup = !['setup', 'run', 'help', '--help', '-h'].includes(cmd) && !cfg.contextId;
if (needSetup) die('还没装好，先跑 agent-reach-browser setup');

const commands = {
  setup: () => cmdSetup(cfg, flags),
  run: () => cmdRun(cfg),
  start: () => cmdStart(cfg),
  stop: () => cmdStop(cfg),
  restart: async () => { await cmdStop(cfg); await cmdStart(cfg); },
  status: () => cmdStatus(cfg),
  login: () => cmdLogin(cfg, rest),
  cookies: () => cmdCookies(cfg, rest[0], flags.json ? 'json' : flags.netscape ? 'netscape' : 'header'),
  'sync-xueqiu': () => cmdSyncXueqiu(cfg),
  uninstall: () => cmdUninstall(cfg),
};
const fn = commands[cmd];
if (!fn) {
  log(fs.readFileSync(SELF, 'utf8').split('\n').slice(1, 17).map((l) => l.replace(/^\/\/ ?/, '')).join('\n'));
  process.exit(cmd === 'help' || cmd === '--help' || cmd === '-h' ? 0 : 1);
}
await fn();
