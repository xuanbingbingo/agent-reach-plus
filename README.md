# agent-reach-plus

在 [agent-reach](https://github.com/Panniantong/agent-reach) 基础上做的**增强分发版**:加了**抖音、快手渠道**,并打包成一键安装的 skill,给（用 Claude Code / 兼容 agent 的）人开箱即用。

> **致谢与许可**:本项目是 agent-reach（作者 Agent Eyes，MIT 协议）的衍生增强版,遵循 MIT。原始版权与协议见 [LICENSE](./LICENSE)。本仓库新增的部分（抖音/快手渠道、install.sh、文档）同样以 MIT 开源。

## 这是什么

agent-reach 是一个"互联网能力路由器"——一条命令访问 13 个平台（GitHub / YouTube / B站 / 小红书 / Twitter / Reddit / V2EX / 雪球 / 小宇宙 / LinkedIn / RSS / Exa 全网搜 / 任意网页）做调研。

**plus 版多了**：
- 第 14 个渠道 **抖音**（搜索 / 取作品 / 话题热点 / 作品数据 / 视频直链），后端走 OpenCLI 复用浏览器登录态。
- 第 15 个渠道 **快手**（搜索 / 单视频详情 / 用户作品列表 / 视频直链），后端走 `opencli browser` 通用浏览器桥 + 快手网页版 GraphQL（快手没有 OpenCLI 原生 adapter），同样复用浏览器登录态。
- **一句话下视频**：装好后，在你的 agent 窗口直接说「帮我下载这个链接的视频 + 链接」，自动认平台（YouTube / B站 / 小红书 / 抖音 / 快手）→ 选对工具 → 下到本地。见 [skill/references/download.md](skill/references/download.md)。

## 安装

```bash
git clone <本仓库地址> agent-reach-plus
cd agent-reach-plus
bash install.sh
```

`install.sh` 会自动:**检查并补齐前置依赖（python3 / pipx / node / ffmpeg）** → 装/更新 agent-reach（pipx）→ 装渠道工具（OpenCLI 等）→ 注入抖音/快手渠道补丁 → 部署 skill 到 `~/.claude/skills/agent-reach/`。

> **依赖自动补齐**：mac 上若装了 [Homebrew](https://brew.sh)，脚本会用 `brew` 自动装齐缺失的 python3/pipx/node/ffmpeg；没装 brew 也会先尝试用 `pip --user` 装 pipx，其余缺啥按平台给出 `brew install` / `apt install` 指引。必需项（python3 / pipx）没装上会停下提示，可选项（node / ffmpeg）缺失只告警不中断（影响对应渠道）。Linux 同理，自动安装目前只对 mac+brew 生效，其余给指引。

### 装完还需手动 3 步（脚本替不了）

1. **OpenCLI 的 Chrome 扩展点一次装**：<https://chromewebstore.google.com/detail/opencli/ildkmabpimmkaediidaifkhjpohdnifk>（小红书/抖音/Twitter 靠它）
2. **在 Chrome 登录要用的平台**（抖音/快手/小红书/Twitter；Reddit 免登录），然后 `agent-reach configure --from-browser chrome` 一把抓 cookie
3. **（可选）转写要免费 Groq key**：<https://console.groq.com> → `agent-reach configure groq-key gsk_xxx`

验证：`agent-reach doctor --json`（抖音/快手应 `status: ok`）。

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

> `user-videos` 必须用 **sec_uid**（传数字 uid 会回退成自己的号）。

### 下载单条视频（⭐主路径 = 分享页直抠 play_url）

> 详细命令与重试链以 [`skill/references/download.md`](skill/references/download.md) 为准；这里是速览。

**为什么默认不绕 sec_uid**：分享页 DOM 里 `MS4wLjABAAAA…` 一大堆但不全是作者（重定向 URL 自带的 `did=`/`iid=` 是设备号、底部推荐位挂别人的号），「抠第一个」常拿错；且 `user-videos` 只返回最近 ~14 条，目标稍早就命中不到。所以**直接从分享页抠播放链接、用 `__vid` 校验**最稳。

```bash
# 1. 短链 → aweme_id（只读重定向头）
curl -sIL "https://v.douyin.com/XXXX/" | grep -i "^location"        # 抠 /share/video/(数字)
# 2. opencli 打开 iesdouyin 分享页（要 Chrome 开 + 登录抖音，等 ~2s 渲染）
opencli browser dy open "https://www.iesdouyin.com/share/video/<aweme_id>/?from_ssr=1"
# 3. ⭐直抠：grep 页面里 douyinvod 链接，过滤 __vid=<aweme_id> 的那条 = play_url
# 4. 解码 &amp;→& 后下载（play_url 带时效签名+地区锁，过期就重取一次）
curl -L -H "Referer: https://www.douyin.com/" -H "User-Agent: Mozilla/5.0..." "<play_url>" -o out.mp4
```

**抠不到时的兜底**：① sec_uid → `opencli douyin user-videos <真sec_uid> -f json` 按 aweme_id 命中取 play_url（⚠️必须传真 sec_uid，数字 uid 会回退成自己的号）；② 免登录 720p：解析分享页 `_ROUTER_DATA` → `play_addr.url_list[0]`，`playwm` 改 `play` 去水印再 curl。

> yt-dlp 的抖音解析器已过期（encrypt_data_miss / Fresh cookies needed），别用。

## 快手用法

快手没有 OpenCLI 原生 adapter，走 `opencli browser` 通用浏览器桥：开一个 kuaishou.com 标签页，在页面上下文里 `fetch` 快手网页版自己的 GraphQL 接口（cookie 由浏览器自动带）。三个接口：

- `visionSearchPhoto` — 关键词搜视频（20条/页，`pcursor` 翻页）
- `visionVideoDetail` — 单视频详情（photoId → 标题/时长/`photoUrl` 直链）
- `visionProfilePhotoList` — 某用户作品列表（userId → 作品 + `photoUrl`）

完整查询体与跑法见 [skill/references/social.md](skill/references/social.md) 快手节。三个实测硬规则：

1. 🔴 GraphQL **必须提交完整 fragment 查询体**，精简查询返回空；
2. cookie 全 HttpOnly，登录态以接口返回 `result == 1` 为准；
3. `photoUrl` 是 CDN 直链，**裸 curl 可下载**（UA+Referer 即可，无需 cookie，比抖音宽松），下载流程见 [skill/references/download.md](skill/references/download.md)。

## 维护说明

- 抖音/快手渠道靠 `patches/apply.py` 注入到已安装的 agent-reach。**`agent-reach` 升级后重跑一次** `patches/apply.py`（用 agent-reach 的 venv python，如 `~/.local/pipx/venvs/agent-reach/bin/python patches/apply.py`）即可恢复。
- 若官方 agent-reach 后续合并了抖音/快手渠道，对应补丁可弃用，直接用官方版。

## 合规

仅限**个人调研 / 内容自动化**。OpenCLI 类渠道用你本人的真实登录态。**禁止批量搬运、去水印二次发布、商用**；作者设置"禁止下载"的内容，技术能取 ≠ 可以使用。写操作（发帖/删帖）默认不碰。

## 目录

```
agent-reach-plus/
├── install.sh          一键安装（macOS / Linux / WSL）
├── install.ps1         一键安装（Windows 原生，自提权）
├── README.md
├── LICENSE             原始 MIT（Agent Eyes）
├── skill/              SKILL.md + references（含抖音/快手 + download 下载流程）
└── patches/
    ├── douyin.py       抖音渠道源码
    ├── kuaishou.py     快手渠道源码
    └── apply.py        幂等注入器（跨平台，douyin + kuaishou 一起管）
```

## 同步到自己的其它机器

改完 `skill/` 之后，把文档推到另一台自己的机器并部署生效（适合目标机连不上 GitHub、没法 `git pull` 的情况）：

```bash
tools/sync-skill.sh user@host                 # 默认 22 端口
tools/sync-skill.sh user@host -p 20023        # 走隧道/非标端口
tools/sync-skill.sh user@host -p 20023 --repo ~/aiProjects/agent-reach-plus   # 顺带更新目标机的仓库副本
```

脚本会先备份目标机现有 skill、传 8 个文档、再逐个 md5 复核，不一致就报错退出。

🔴 **只同步「能力」，不同步「数据」**：目标机的 `~/.agent-reach/config.yaml`
（cookie / api key / 登录态）脚本一个字节都不碰——那是各人自己的凭据，必须在目标机本人登录后
用 `agent-reach configure --from-browser chrome` 自己抓。

