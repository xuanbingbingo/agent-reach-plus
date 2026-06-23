#!/usr/bin/env bash
# agent-reach-plus 一键安装
# = 官方 agent-reach + 抖音渠道 + skill 文档
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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

echo "▶ 1/5 安装/更新 agent-reach (pipx)"
if ! command -v pipx >/dev/null 2>&1; then
  echo "  ❌ 没有 pipx。先装：python3 -m pip install --user pipx && python3 -m pipx ensurepath"
  echo "     然后重开终端再跑本脚本。"
  exit 1
fi
# agent-reach 不在 PyPI，官方安装源是 GitHub main.zip
AR_SRC="https://github.com/Panniantong/agent-reach/archive/main.zip"
pipx install "$AR_SRC" 2>/dev/null || pipx install --force "$AR_SRC"

echo "▶ 2/5 安装渠道工具（OpenCLI / bili-cli 等）"
agent-reach install || echo "  ⚠️ agent-reach install 有非致命报错，继续。"

echo "▶ 3/5 安装 BBDown（B站视频下载，便携版）"
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

echo "▶ 4/5 注入抖音渠道补丁"
VENV_BASE="$(pipx environment --value PIPX_LOCAL_VENVS 2>/dev/null || true)"
VENV_PY="${VENV_BASE:-$HOME/.local/pipx/venvs}/agent-reach/bin/python"
if [ ! -x "$VENV_PY" ]; then
  echo "  ❌ 找不到 agent-reach 的 venv python：$VENV_PY"; exit 1
fi
"$VENV_PY" "$HERE/patches/apply.py"

echo "▶ 5/5 部署 skill → ~/.claude/skills/agent-reach/"
DEST="$HOME/.claude/skills/agent-reach"
mkdir -p "$DEST/references"
cp "$HERE/skill/SKILL.md" "$DEST/SKILL.md"
cp "$HERE"/skill/references/*.md "$DEST/references/"

cat <<'EOF'

✅ 安装完成。还有 3 件必须你本人手动做（脚本无法替代）：

  1) 装 OpenCLI 的 Chrome 扩展（点一次）：
     https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk
     装完保持 Chrome 开着，跑 `opencli doctor` 应显示 Extension: connected

  2) 在同一个 Chrome 里登录你要用的平台（抖音 / 小红书 / Twitter；Reddit 免登录）
     一次性提取 cookie：agent-reach configure --from-browser chrome

  3) （可选）小宇宙播客 / 本地录音转文字需要免费 Groq key：
     注册 https://console.groq.com → agent-reach configure groq-key gsk_xxx

验证全部渠道：agent-reach doctor --json
（抖音应显示 status: ok / active_backend: OpenCLI）

装好后，在你的 agent 窗口直接说一句即可下载视频，例如：
  「帮我下载这个链接的视频 <粘贴 YouTube/B站/小红书/抖音 链接>」
  → 自动认平台、选工具、下到本地。
  （B站合流需系统装 ffmpeg：brew install ffmpeg / apt install ffmpeg）
EOF
