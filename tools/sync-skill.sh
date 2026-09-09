#!/usr/bin/env bash
# 把本仓库的 skill/ 推到另一台机器并部署生效。
#
# 用途：改完 skill/ 之后，同步给自己的其它机器。
# 适合「目标机连不上 GitHub、没法 git pull」的情况（国内机器很常见）。
# 只同步文档，不碰目标机的 ~/.agent-reach/config.yaml（那里面是各人自己的
# cookie / api key，属于数据不属于能力，绝不跨机复制）。
#
# 用法：
#   tools/sync-skill.sh user@host                 # 默认 22 端口
#   tools/sync-skill.sh user@host -p 20023        # 走隧道/非标端口
#   tools/sync-skill.sh user@host --repo ~/aiProjects/agent-reach-plus
#
set -euo pipefail

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "用法: $0 user@host [-p PORT] [--repo 目标机上的仓库路径]"; exit 1; }
shift

PORT=22
REMOTE_REPO=""              # 留空 = 不更新目标机的仓库副本，只部署 skill
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--port) PORT="$2"; shift 2 ;;
    --repo)    REMOTE_REPO="$2"; shift 2 ;;
    *) echo "未知参数: $1"; exit 1 ;;
  esac
done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$HERE/skill"
[ -d "$SRC/references" ] || { echo "❌ 找不到 $SRC/references，请在仓库内运行"; exit 1; }

SSH=(ssh -p "$PORT" "$TARGET")
SCP=(scp -P "$PORT" -q)

echo "▶ 1/4 目标机备份现有 skill"
"${SSH[@]}" 'zsh -lc '"'"'
  D=~/.claude/skills/agent-reach
  [ -d "$D" ] && cp -a "$D" "$D.bak-$(date +%Y%m%d_%H%M%S)" && echo "  已备份 $D.bak-*" || echo "  目标机原本没装，将新建"
  mkdir -p "$D/references"
'"'"''

echo "▶ 2/4 传 skill 文档"
"${SCP[@]}" "$SRC/SKILL.md"           "$TARGET:~/.claude/skills/agent-reach/SKILL.md"
"${SCP[@]}" "$SRC"/references/*.md    "$TARGET:~/.claude/skills/agent-reach/references/"

if [ -n "$REMOTE_REPO" ]; then
  echo "▶ 3/4 同步目标机上的仓库副本 → $REMOTE_REPO/skill"
  "${SSH[@]}" "zsh -lc 'mkdir -p $REMOTE_REPO/skill/references'"
  "${SCP[@]}" "$SRC/SKILL.md"        "$TARGET:$REMOTE_REPO/skill/SKILL.md"
  "${SCP[@]}" "$SRC"/references/*.md "$TARGET:$REMOTE_REPO/skill/references/"
else
  echo "▶ 3/4 跳过仓库副本（未传 --repo）"
fi

echo "▶ 4/4 两端 md5 复核"
FAIL=0
for f in SKILL.md $(cd "$SRC/references" && ls *.md | sed 's|^|references/|'); do
  L=$(md5 -q "$SRC/$f" 2>/dev/null || md5sum "$SRC/$f" | cut -d' ' -f1)
  R=$("${SSH[@]}" "zsh -lc 'md5 -q ~/.claude/skills/agent-reach/$f 2>/dev/null || md5sum ~/.claude/skills/agent-reach/$f | cut -d\" \" -f1'" 2>/dev/null | tr -d '\r')
  if [ "$L" = "$R" ]; then echo "  ✅ $f"; else echo "  ❌ $f  (本地 ${L:0:8} / 远端 ${R:0:8})"; FAIL=1; fi
done

[ "$FAIL" = 0 ] && echo "✅ 同步完成，8 个文件全部一致" || { echo "❌ 有文件不一致，请检查"; exit 1; }

cat <<'TIP'

提示：本脚本只同步「能力」（skill 文档）。目标机还需要自己完成的「数据」部分：
  - 在目标机自己的 Chrome 里登录各平台
  - 在目标机跑 agent-reach configure --from-browser chrome
  - 目标机自己的 groq key / gh auth login
这些是各人自己的凭据，不跨机复制。
TIP
