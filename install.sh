#!/usr/bin/env bash
# agent-reach-plus 一键安装
# = 官方 agent-reach + 抖音、快手渠道 + skill 文档
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 可选：--with-browser 额外装「无头采集浏览器」（OpenCLI 渠道不再借用日常 Chrome）
#       --proxy URL     海外站（X/Reddit/Google 验证等）走的代理，如 http://127.0.0.1:7890；国内站始终直连
WITH_BROWSER=0; BROWSER_PROXY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --with-browser) WITH_BROWSER=1; shift ;;
    --proxy) BROWSER_PROXY="${2:-}"; shift 2 ;;
    *) echo "未知参数：$1（可用：--with-browser [--proxy URL]）"; exit 1 ;;
  esac
done

# —— Windows 守卫：本脚本是 bash，面向 macOS / Linux / WSL ——
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    cat <<'WIN'
检测到 Windows（git-bash / MSYS / Cygwin）。本 bash 脚本面向 macOS / Linux。

Windows 用户请改用原生 PowerShell 安装器（推荐，抖音/小红书等全可用）：
  在仓库目录下的 PowerShell 执行：
      powershell -ExecutionPolicy Bypass -File .\install.ps1

（或备选 WSL：wsl --install -d Ubuntu，进 Ubuntu 后 apt 装 python3-pip nodejs npm git pipx ffmpeg
  再 bash install.sh —— 但 WSL 下 OpenCLI 类渠道[抖音/小红书/Twitter/Reddit]的 Chrome 扩展
  跨 WSL↔Windows 边界通常不通，只有 YouTube/B站/GitHub/雪球/RSS/网页可用。要抖音就用 install.ps1。）
WIN
    exit 1 ;;
esac

echo "▶ 1/6 检查 / 自动补齐前置依赖（python3 / pipx / node / ffmpeg）"
OS="$(uname -s)"
have(){ command -v "$1" >/dev/null 2>&1; }
MISSING_MANDATORY=0
BREW=""
if [ "$OS" = "Darwin" ] && have brew; then BREW="yes"; fi
if [ "$OS" = "Darwin" ] && [ -z "$BREW" ]; then
  echo "  ℹ️ 没检测到 Homebrew（mac 自动装依赖靠它）。建议先装 brew，之后本脚本即可自动补齐："
  echo '       /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  echo "     不装 brew 也行，但下面缺的依赖需按提示手动装。"
fi

# 自动装一个工具：mac+brew 直接 brew install；否则按平台给手动指引
brew_or_guide(){   # $1=命令 $2=brew包 $3=mandatory(1/0) $4=说明
  cmd="$1"; pkg="$2"; mand="$3"; desc="$4"
  if have "$cmd"; then echo "  ✅ $cmd 已就绪"; return 0; fi
  if [ -n "$BREW" ]; then
    echo "  • 缺 $cmd，brew 安装 $pkg ..."
    brew install "$pkg" >/dev/null 2>&1 || echo "    ⚠️ brew install $pkg 失败，请手动重试"
    if have "$cmd"; then echo "  ✅ $cmd 已装好"; return 0; fi
  fi
  if [ "$mand" = "1" ]; then
    echo "  ❌ 必需依赖缺失：$cmd（$desc）"; MISSING_MANDATORY=1
  else
    echo "  ⚠️ 可选依赖缺失：$cmd（$desc）—相关渠道暂不可用，可稍后补 $pkg"
  fi
  if [ "$OS" = "Darwin" ]; then
    echo "      mac 手动装：brew install $pkg"
  else
    echo "      Linux 手动装：sudo apt install -y $pkg（或对应包管理器）"
  fi
}

# python3：mac 通常自带；缺了才装
brew_or_guide python3 python 1 "运行 agent-reach 的 Python 解释器"

# pipx：brew 优先 → 无 brew 自动退回 pip --user → 仍失败才报错
if have pipx; then
  echo "  ✅ pipx 已就绪"
else
  if [ -n "$BREW" ]; then
    echo "  • 缺 pipx，brew 安装 ..."; brew install pipx >/dev/null 2>&1 || true
  fi
  if ! have pipx && have python3; then
    echo "  • 用 pip 安装 pipx（--user）..."
    python3 -m pip install --user pipx >/dev/null 2>&1 || true
    python3 -m pipx ensurepath >/dev/null 2>&1 || true
    export PATH="$HOME/.local/bin:$PATH"
  fi
  if have pipx; then
    echo "  ✅ pipx 已就绪"
  else
    echo "  ❌ pipx 仍缺失。手动装：python3 -m pip install --user pipx && python3 -m pipx ensurepath，重开终端再跑。"
    MISSING_MANDATORY=1
  fi
fi

# node：OpenCLI 类渠道（抖音/小红书/Twitter/Reddit）运行时；ffmpeg：B站合流/音视频处理
brew_or_guide node node 0 "OpenCLI 渠道(抖音/小红书等)运行时"
brew_or_guide ffmpeg ffmpeg 0 "B站合流、音视频处理"

if [ "$MISSING_MANDATORY" = "1" ]; then
  echo ""
  echo "❌ 有必需依赖没装上（见上方 ❌）。补齐后重跑本脚本。"
  exit 1
fi
pipx ensurepath >/dev/null 2>&1 || true

echo "▶ 2/6 安装/更新 agent-reach (pipx)"
# agent-reach 不在 PyPI，官方安装源是 GitHub main.zip
AR_SRC="https://github.com/Panniantong/agent-reach/archive/main.zip"
pipx install "$AR_SRC" 2>/dev/null || pipx install --force "$AR_SRC"

echo "▶ 3/6 安装渠道工具（OpenCLI / bili-cli 等）"
agent-reach install || echo "  ⚠️ agent-reach install 有非致命报错，继续。"

echo "▶ 4/6 安装 BBDown（B站视频下载，便携版）"
case "$(uname -s)-$(uname -m)" in
  Darwin-arm64)   BB_PAT="osx-arm64" ;;
  Darwin-x86_64)  BB_PAT="osx-x64" ;;
  Linux-x86_64)   BB_PAT="linux-x64" ;;
  Linux-aarch64)  BB_PAT="linux-arm64" ;;
  *)              BB_PAT="" ;;
esac
if [ -z "$BB_PAT" ]; then
  echo "  ⚠️ 未识别平台（$(uname -s)-$(uname -m)），跳过 BBDown。B站下载需手动装：https://github.com/nilaoda/BBDown/releases"
elif [ -x "$HOME/.agent-reach/bin/BBDown" ]; then
  echo "  ℹ️ BBDown 已存在，跳过。"
else
  mkdir -p "$HOME/.agent-reach/bin"
  # 整步可选、失败不中断（|| true 防止 set -e 在限流/无匹配时掐断脚本）
  BB_URL="$(curl -fsSL "https://api.github.com/repos/nilaoda/BBDown/releases/latest" 2>/dev/null \
            | grep -oE "https://[^\"]*BBDown[^\"]*${BB_PAT}\.zip" | head -1 || true)"
  # API 取不到（限流/无网）→ 兜底用钉死的稳定版直链
  [ -z "$BB_URL" ] && BB_URL="https://github.com/nilaoda/BBDown/releases/download/1.6.3/BBDown_1.6.3_20240814_${BB_PAT}.zip"
  if [ -n "$BB_URL" ] && curl -fsSL "$BB_URL" -o /tmp/bbdown.zip 2>/dev/null; then
    unzip -o -q /tmp/bbdown.zip -d "$HOME/.agent-reach/bin" && chmod +x "$HOME/.agent-reach/bin/BBDown" 2>/dev/null
    rm -f /tmp/bbdown.zip
    echo "  ✅ BBDown → ~/.agent-reach/bin/BBDown（B站合流需系统装 ffmpeg）"
  else
    echo "  ⚠️ 没拉到 BBDown，B站下载可稍后手动装：https://github.com/nilaoda/BBDown/releases"
  fi
fi

echo "▶ 5/6 注入抖音、快手渠道补丁"
VENV_BASE="$(pipx environment --value PIPX_LOCAL_VENVS 2>/dev/null || true)"
VENV_PY="${VENV_BASE:-$HOME/.local/pipx/venvs}/agent-reach/bin/python"
if [ ! -x "$VENV_PY" ]; then
  echo "  ❌ 找不到 agent-reach 的 venv python：$VENV_PY"; exit 1
fi
"$VENV_PY" "$HERE/patches/apply.py"

echo "▶ 6/6 部署 skill → ~/.claude/skills/agent-reach/"
DEST="$HOME/.claude/skills/agent-reach"
mkdir -p "$DEST/references"
cp "$HERE/skill/SKILL.md" "$DEST/SKILL.md"
cp "$HERE"/skill/references/*.md "$DEST/references/"

# 无头采集浏览器的程序总是装上（很小），是否启用由 --with-browser 决定
BR_DIR="$HOME/.agent-reach/browser"
mkdir -p "$BR_DIR" "$HOME/.agent-reach/bin" "$HOME/.local/bin"
cp "$HERE/browser/agent-reach-browser.mjs" "$BR_DIR/"
printf '#!/bin/sh\nexec node "%s/agent-reach-browser.mjs" "$@"\n' "$BR_DIR" > "$HOME/.agent-reach/bin/agent-reach-browser"
chmod +x "$HOME/.agent-reach/bin/agent-reach-browser"
ln -sf "$HOME/.agent-reach/bin/agent-reach-browser" "$HOME/.local/bin/agent-reach-browser"

if [ "$WITH_BROWSER" = "1" ]; then
  echo "▶ 附加：安装无头采集浏览器"
  if have node && have opencli; then
    "$HOME/.agent-reach/bin/agent-reach-browser" setup ${BROWSER_PROXY:+--proxy "$BROWSER_PROXY"} \
      || echo "  ⚠️ 无头浏览器安装失败，可稍后单独跑：agent-reach-browser setup"
  else
    echo "  ⚠️ 缺 node 或 opencli，跳过。补齐后跑：agent-reach-browser setup"
  fi
fi

if [ "$WITH_BROWSER" = "1" ]; then cat <<'EOF'

✅ 安装完成（含无头采集浏览器）。还需你本人做：

  1) 在无头浏览器里登录要用的平台（弹一次窗口，登完关掉即回后台无头）：
     agent-reach-browser login https://www.douyin.com https://www.xiaohongshu.com https://passport.bilibili.com/login https://x.com/i/flow/login
     （不用装 Chrome 扩展、不用开日常 Chrome）
     雪球：再 login https://xueqiu.com，然后 agent-reach-browser sync-xueqiu

  2) （可选）转写要 Groq key：agent-reach configure groq-key gsk_xxx

验证：agent-reach-browser status；opencli douyin search "AI" -f json
EOF
exit 0
fi

cat <<'EOF'

✅ 安装完成。还有 3 件必须你本人手动做（脚本无法替代）：

  1) 装 OpenCLI 的 Chrome 扩展（点一次）：
     https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk
     装完保持 Chrome 开着，跑 `opencli doctor` 应显示 Extension: connected

  2) 在同一个 Chrome 里登录你要用的平台（抖音 / 快手 / 小红书 / Twitter；Reddit 免登录）
     一次性提取 cookie：agent-reach configure --from-browser chrome

  3) （可选）小宇宙播客 / 本地录音转文字需要免费 Groq key：
     注册 https://console.groq.com → agent-reach configure groq-key gsk_xxx

验证全部渠道：agent-reach doctor --json
（抖音、快手应显示 status: ok）

装好后，在你的 agent 窗口直接说一句即可下载视频，例如：
  「帮我下载这个链接的视频 <粘贴 YouTube/B站/小红书/抖音/快手 链接>」
  → 自动认平台、选工具、下到本地。
  （B站合流需系统装 ffmpeg：brew install ffmpeg / apt install ffmpeg）

不想让采集打开/占用你的日常 Chrome？装无头采集浏览器：
  agent-reach-browser setup [--proxy http://127.0.0.1:7890]
  （或重跑 bash install.sh --with-browser）
EOF
