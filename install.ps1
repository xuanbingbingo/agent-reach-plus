# agent-reach-plus · Windows 原生安装器 (PowerShell)
# = 官方 agent-reach + 抖音、快手渠道 + skill，全部跑在原生 Windows（不用 WSL）
# 用法：在 PowerShell 里  cd 到本仓库目录，执行：  powershell -ExecutionPolicy Bypass -File .\install.ps1
# Continue（不要 Stop）：pipx/agent-reach 会把正常进度写到 stderr，
# Stop 下会被当成终止错误中断安装。真失败靠下面的 Have/Test-Path 显式判断。
$ErrorActionPreference = 'Continue'
# 让 Python/控制台用 UTF-8：否则中文 Windows 默认 GBK，agent-reach 打印 emoji(✨)会崩
$env:PYTHONUTF8 = '1'
$env:PYTHONIOENCODING = 'utf-8'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8; chcp 65001 > $null } catch {}
$HERE = Split-Path -Parent $MyInvocation.MyCommand.Path

function Have($c) { [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function Refresh-Path {
  $m = [Environment]::GetEnvironmentVariable('Path','Machine')
  $u = [Environment]::GetEnvironmentVariable('Path','User')
  $env:Path = "$m;$u"
}
# 选一个“真” python（绕开 Microsoft Store 的占位别名）：优先 py 启动器
function Get-Python {
  if (Have py) { return 'py' }
  $cand = Get-Command python -ErrorAction SilentlyContinue
  # WindowsApps 下的是商店别名，不算
  if ($cand -and $cand.Source -notlike '*\WindowsApps\*') { return $cand.Source }
  return $null
}

Write-Host "== agent-reach-plus Windows 安装器 ==" -ForegroundColor Cyan

# —— 自提权 ——（实测：winget 装 git/python 等机器级包会弹 UAC 安全桌面，
#    非管理员下每个包都弹、且 UAC 无法被脚本自动点。提权一次后整条链不再弹。）
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
  [Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
  Write-Host "需要管理员权限（winget 安装会弹 UAC）。点'是'后会以管理员重开窗口继续装……" -ForegroundColor Yellow
  $hostExe = (Get-Process -Id $PID).Path   # 当前宿主：powershell.exe 或 pwsh.exe
  if (-not $hostExe) { $hostExe = 'powershell.exe' }
  Start-Process -FilePath $hostExe -Verb RunAs -ArgumentList @(
    '-ExecutionPolicy','Bypass','-NoExit','-File', $PSCommandPath)
  exit
}

# 0) winget
if (-not (Have winget)) {
  Write-Error "缺少 winget（App Installer）。请到 Microsoft Store 装 'App Installer' 后重试。"; exit 1
}
$wg = @('-e','--silent','--accept-source-agreements','--accept-package-agreements')

# 1) 前置：Python / Node / Git / ffmpeg（缺什么装什么）
Write-Host "▶ 1/5 前置工具 (winget)" -ForegroundColor Yellow
if (-not (Get-Python))  { Write-Host "  装 Python...";  winget install @wg --id Python.Python.3.12 }
if (-not (Have node))   { Write-Host "  装 Node.js..."; winget install @wg --id OpenJS.NodeJS.LTS }
if (-not (Have git))    { Write-Host "  装 Git...";     winget install @wg --id Git.Git }
if (-not (Have ffmpeg)) { Write-Host "  装 ffmpeg (B站合流用)..."; winget install @wg --id Gyan.FFmpeg }
Refresh-Path
$PY = Get-Python
if (-not $PY) { Write-Error "Python 安装后仍找不到，请重开 PowerShell 再跑一次本脚本。"; exit 1 }

# 2) pipx + agent-reach（GitHub zip，PyPI 上没有此包）
Write-Host "▶ 2/5 安装 agent-reach (pipx)" -ForegroundColor Yellow
& $PY -m pip install --user --upgrade pipx | Out-Null
& $PY -m pipx ensurepath | Out-Null
Refresh-Path
$AR = 'https://github.com/Panniantong/agent-reach/archive/main.zip'
& $PY -m pipx install $AR 2>$null
if ($LASTEXITCODE -ne 0) { & $PY -m pipx install --force $AR }
Refresh-Path

# 3) 渠道工具（agent-reach 自己装 opencli/yt-dlp/mcporter 等）
Write-Host "▶ 3/5 安装渠道工具 (OpenCLI 等)" -ForegroundColor Yellow
if (Have agent-reach) { agent-reach install } else { Write-Warning "agent-reach 不在 PATH，可能需重开 PowerShell；跳过 install" }

# 4) 注入抖音、快手渠道补丁（用 agent-reach 的 venv python）
Write-Host "▶ 4/5 注入抖音、快手渠道" -ForegroundColor Yellow
$venvBase = (& $PY -m pipx environment --value PIPX_LOCAL_VENVS) 2>$null
$venvPy = Join-Path $venvBase 'agent-reach\Scripts\python.exe'
if (Test-Path $venvPy) {
  & $venvPy (Join-Path $HERE 'patches\apply.py')
} else {
  Write-Warning "找不到 agent-reach 的 venv python：$venvPy（跳过抖音/快手注入，可稍后手动跑 patches\apply.py）"
}

# 5) 下载 BBDown（B站）+ 部署 skill
Write-Host "▶ 5/5 BBDown + 部署 skill" -ForegroundColor Yellow
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'win-arm64' } else { 'win-x64' }
$bbDir = Join-Path $env:USERPROFILE '.agent-reach\bin'
New-Item -ItemType Directory -Force -Path $bbDir | Out-Null
if (-not (Test-Path (Join-Path $bbDir 'BBDown.exe'))) {
  try {
    $rel = Invoke-RestMethod 'https://api.github.com/repos/nilaoda/BBDown/releases/latest' -Headers @{'User-Agent'='arp'}
    $asset = $rel.assets | Where-Object { $_.browser_download_url -match "$arch\.zip$" } | Select-Object -First 1
    $url = if ($asset) { $asset.browser_download_url } else { "https://github.com/nilaoda/BBDown/releases/download/1.6.3/BBDown_1.6.3_20240814_$arch.zip" }
  } catch {
    $url = "https://github.com/nilaoda/BBDown/releases/download/1.6.3/BBDown_1.6.3_20240814_$arch.zip"
  }
  try {
    Invoke-WebRequest $url -OutFile "$env:TEMP\bbdown.zip" -UseBasicParsing
    Expand-Archive "$env:TEMP\bbdown.zip" -DestinationPath $bbDir -Force
    Remove-Item "$env:TEMP\bbdown.zip" -Force
    Write-Host "  BBDown -> $bbDir\BBDown.exe"
  } catch { Write-Warning "BBDown 没下到（B站下载用），可稍后手动装：https://github.com/nilaoda/BBDown/releases" }
}

$dest = Join-Path $env:USERPROFILE '.claude\skills\agent-reach'
New-Item -ItemType Directory -Force -Path (Join-Path $dest 'references') | Out-Null
Copy-Item (Join-Path $HERE 'skill\SKILL.md') (Join-Path $dest 'SKILL.md') -Force
Copy-Item (Join-Path $HERE 'skill\references\*.md') (Join-Path $dest 'references\') -Force

Write-Host ""
Write-Host "完成。还有 3 件必须手动做：" -ForegroundColor Green
Write-Host "  1) 装 OpenCLI 的 Chrome 扩展（点一次）：https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk"
Write-Host "  2) 在 Chrome 登录要用的平台（抖音/快手/小红书/Twitter；Reddit 免登录），再 agent-reach configure --from-browser chrome"
Write-Host "  3) （可选）转写要免费 Groq key：https://console.groq.com  ->  agent-reach configure groq-key gsk_xxx"
Write-Host "验证：agent-reach doctor --json（抖音、快手应 status: ok）"
Write-Host "提示：若 agent-reach / python 命令找不到，重开一个 PowerShell 窗口再试（PATH 需刷新）。"
