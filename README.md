# agent-reach-plus

在 [agent-reach](https://github.com/Panniantong/agent-reach) 基础上做的**增强分发版**:加了**抖音渠道**,并打包成一键安装的 skill,给（用 Claude Code / 兼容 agent 的）人开箱即用。

> **致谢与许可**:本项目是 agent-reach（作者 Agent Eyes，MIT 协议）的衍生增强版,遵循 MIT。原始版权与协议见 [LICENSE](./LICENSE)。本仓库新增的部分（抖音渠道、install.sh、文档）同样以 MIT 开源。

## 这是什么

agent-reach 是一个"互联网能力路由器"——一条命令访问 13 个平台（GitHub / YouTube / B站 / 小红书 / Twitter / Reddit / V2EX / 雪球 / 小宇宙 / LinkedIn / RSS / Exa 全网搜 / 任意网页）做调研。

**plus 版多了**：
- 第 14 个渠道 **抖音**（搜索 / 取作品 / 话题热点 / 作品数据 / 视频直链），后端走 OpenCLI 复用浏览器登录态。
- **一句话下视频**：装好后，在你的 agent 窗口直接说「帮我下载这个链接的视频 + 链接」，自动认平台（YouTube / B站 / 小红书 / 抖音）→ 选对工具 → 下到本地。见 [skill/references/download.md](skill/references/download.md)。

## 安装

```bash
git clone <本仓库地址> agent-reach-plus
cd agent-reach-plus
bash install.sh
```

`install.sh` 会自动:装/更新 agent-reach（pipx）→ 装渠道工具（OpenCLI 等）→ 注入抖音渠道补丁 → 部署 skill 到 `~/.claude/skills/agent-reach/`。

### 装完还需手动 3 步（脚本替不了）

1. **OpenCLI 的 Chrome 扩展点一次装**：<https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk>（小红书/抖音/Twitter 靠它）
2. **在 Chrome 登录要用的平台**（抖音/小红书/Twitter；Reddit 免登录），然后 `agent-reach configure --from-browser chrome` 一把抓 cookie
3. **（可选）转写要免费 Groq key**：<https://console.groq.com> → `agent-reach configure groq-key gsk_xxx`

验证：`agent-reach doctor --json`（抖音应 `status: ok`）。

> 平台：**macOS / Linux 原生支持**。安装与下载流程已在隔离沙盒端到端验证（agent-reach 装源、抖音渠道注入、BBDown、skill 部署全通过）。

## Windows 用户（原生，推荐）

Windows 用 **`install.ps1`**（原生 PowerShell，不用 WSL，抖音/小红书等全可用，因为 opencli 和 Chrome 都在 Windows 本机）：

```powershell
# 在仓库目录下，PowerShell 执行：
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

脚本会：**自提权**（弹一次 UAC 点"是"）→ winget 装 Python/Node/Git/ffmpeg → pipx 装 agent-reach → 注入抖音渠道 → 下 BBDown.exe → 部署 skill 到 `%USERPROFILE%\.claude\skills\agent-reach`。装完同样需手动：装 OpenCLI Chrome 扩展、登录平台、（可选）配 Groq key。

> **已在真机 Win11 ARM 上端到端验证跑通**（前置工具 → agent-reach → 抖音渠道注入 → BBDown.exe → skill 部署，全程到绿色"完成"）。测试中发现并修掉的 4 个 Windows 坑（现已内置处理）：
> 1. `agent-reach` 不在 PyPI → 装源用 GitHub `main.zip`；
> 2. 机器级 winget 安装弹 **UAC 安全桌面** → 脚本**自提权**，开头点一次"是"即可，后续不再弹；
> 3. 中文 Windows 控制台默认 GBK，Python 打印 emoji(✨) 会崩 → 脚本设 `PYTHONUTF8` + `chcp 65001`；
> 4. pipx/agent-reach 把进度写 stderr 被 `Stop` 误判终止 → 改 `Continue`，真失败靠显式判断。
>
> 另：裸系统 git/node/pipx 全无、python 是商店占位别名（故用 winget 实装 + `py` 启动器）；`install.ps1` 存为 UTF-8 BOM（否则 PS 5.1 按 GBK 读中文乱码）；Win11 ARM 自动取 BBDown 的 `win-arm64` 包。

### 备选：WSL

也可在 WSL(Ubuntu) 里跑 `install.sh`（走 Linux 路径）。但 **WSL 下 OpenCLI 类渠道（抖音/小红书/Twitter/Reddit）的 Chrome 扩展跨 WSL↔Windows 边界通常不通**，只有 YouTube/B站/GitHub/雪球/RSS/网页可用。所以要抖音/小红书，**用上面的原生 `install.ps1`，不要用 WSL**。`install.sh` 在 git-bash/MSYS 下会直接给 WSL 指引并退出。

## 抖音用法

```bash
opencli douyin search "关键词" -f json          # 搜视频
opencli douyin user-videos <sec_uid> -f json    # 某用户作品（含 play_url 直链）
opencli douyin hashtag <action> -f yaml         # 话题热点词
opencli douyin stats <aweme_id> -f yaml         # 作品数据
```

> `user-videos` 必须用 **sec_uid**（传数字 uid 会回退成自己）。拿 sec_uid：短链 `v.douyin.com` 解析出 aweme_id → 抓 `iesdouyin.com/share/video/<aweme_id>/?from_ssr=1` 用正则 `MS4wLjABAAAA[A-Za-z0-9_-]{20,}` 抠作者 sec_uid。

### 下载视频（A 首选画质高 / B 兜底免登录）

两种方法**都能下别人的作品**，都先抓分享页拿 sec_uid/aweme_id，区别只在最后取流：

| | A：opencli（首选） | B：reflow 页（兜底） |
|---|---|---|
| 取流 | `user-videos <真sec_uid>` 返回的 `play_url` | 分享页 `_ROUTER_DATA` 里的 `play_addr` |
| 画质 | **高，实测到 1080p / 4Mbps** | 较低，720p 转码 |
| 依赖 | **要 Chrome 开 + 登录抖音** | **纯 curl，免登录、不用 opencli** |

```bash
# A（高画质，要登录）：
opencli douyin user-videos <真sec_uid> --limit 20 -f json   # 取每条 play_url
curl -L "<play_url>" -H "Referer: https://www.douyin.com/" -o out.mp4

# B（免登录，720p）：解析分享页 _ROUTER_DATA → play_addr.url_list[0]
#   把 URL 里的 playwm 改成 play 去水印，再 curl（带移动 UA + Referer）
```

> ⚠️ 坑：`user-videos` 传**数字 uid 会回退成你自己的号**，必须传真 sec_uid。
> yt-dlp 的抖音解析器已过期（encrypt_data_miss / Fresh cookies needed），别用。两种方法都拿不到作者原始母带。

## 维护说明

- 抖音渠道靠 `patches/apply.py` 注入到已安装的 agent-reach。**`agent-reach` 升级后重跑一次** `python3 patches/apply.py`（用 agent-reach 的 venv python）即可恢复。
- 若官方 agent-reach 后续合并了抖音渠道，本补丁可弃用，直接用官方版。

## 合规

仅限**个人调研 / 内容自动化**。OpenCLI 类渠道用你本人的真实登录态。**禁止批量搬运、去水印二次发布、商用**；作者设置"禁止下载"的内容，技术能取 ≠ 可以使用。写操作（发帖/删帖）默认不碰。

## 目录

```
agent-reach-plus/
├── install.sh          一键安装（macOS / Linux / WSL）
├── install.ps1         一键安装（Windows 原生，自提权）
├── README.md
├── LICENSE             原始 MIT（Agent Eyes）
├── skill/              SKILL.md + references（含抖音 + download 下载流程）
└── patches/
    ├── douyin.py       抖音渠道源码
    └── apply.py        幂等注入器（跨平台）
```
