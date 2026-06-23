#!/usr/bin/env bash
# agent-reach-plus 一键安装
# = 官方 agent-reach + 抖音渠道 + skill 文档
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "▶ 1/4 安装/更新 agent-reach (pipx)"
if ! command -v pipx >/dev/null 2>&1; then
  echo "  ❌ 没有 pipx。先装：python3 -m pip install --user pipx && python3 -m pipx ensurepath"
  echo "     然后重开终端再跑本脚本。"
  exit 1
fi
pipx install agent-reach 2>/dev/null || pipx upgrade agent-reach || true

echo "▶ 2/4 安装渠道工具（OpenCLI / bili-cli 等）"
agent-reach install || echo "  ⚠️ agent-reach install 有非致命报错，继续。"

echo "▶ 3/4 注入抖音渠道补丁"
VENV_BASE="$(pipx environment --value PIPX_LOCAL_VENVS 2>/dev/null || true)"
VENV_PY="${VENV_BASE:-$HOME/.local/pipx/venvs}/agent-reach/bin/python"
if [ ! -x "$VENV_PY" ]; then
  echo "  ❌ 找不到 agent-reach 的 venv python：$VENV_PY"; exit 1
fi
"$VENV_PY" "$HERE/patches/apply.py"

echo "▶ 4/4 部署 skill → ~/.claude/skills/agent-reach/"
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
EOF
