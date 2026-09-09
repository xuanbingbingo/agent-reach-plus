# 视频/播客

YouTube、B站、小宇宙播客的字幕和转录。

## YouTube (yt-dlp)

> 🔴 **大陆网络必须自备 HTTP 代理**：youtube.com 与 googlevideo.com 直连均不可达。
> 命令行工具**不读系统代理开关**，必须显式传，或写进 `~/.config/yt-dlp/config`：
> ```bash
> yt-dlp --proxy http://HOST:PORT ...
> ```
> 注意本地那些「只给某个 API 转发」的回环代理（各类 Claude/AI 网关）白名单里通常
> **不含 YouTube**，别指望它们能顺带转发。
> ⚠️ 尽量用**规则模式**而不是 TUN/增强模式：TUN 在网卡层接管全局流量，
> 可能把本机其它长连接（如给编码会话供网的链路）一起捞进去导致断线。

> 🔴 **媒体流 403 Forbidden 的两个真因**（别再逐个换 `player_client` 试）：
> 1. **yt-dlp 版本旧** —— 实测 2026.06.09 取元信息正常、一拉媒体必 403，
>    `tv/ios/android_vr/web_embedded/mweb` 五种 client 全无效；升到 2026.08.19 一次通过。
> 2. **代理节点轮换** —— 媒体 URL 里绑了 `ip=xxx`，取元信息和拉流之间若切了节点就 403。
>    重跑一次通常即好；要根治就在代理客户端里把 YouTube 规则固定单节点（别用 url-test / load-balance）。

> 🔴 **启动慢会让 `agent-reach doctor` 误报 `youtube: error`**：doctor 跑的是
> `yt-dlp --version`，**超时线 10 秒**。yt-dlp 的**独立打包二进制**（自解压那种）冷启可达 9 秒，
> 卡在线上 → doctor 报错，但**下载其实完全正常**，是红灯误导。
> 判据：`time yt-dlp --version`。超过 1 秒就换 Python 版（`pipx install yt-dlp` / `brew install yt-dlp`），
> 实测同机 8.9s → 94ms。

> ⚠️ **Homebrew 版被 pip 遮蔽的坑**：若 `brew list --versions yt-dlp` 显示新版但 `yt-dlp --version` 是旧版，
> 检查 `/opt/homebrew/bin/yt-dlp` 是不是被 pip 装的 launcher 脚本顶掉了 brew 软链（`ls -la` 看是不是符号链接）。
> 修：`brew link --overwrite yt-dlp`。
> 🔴 顺带拆 pip 那份时注意：`pip uninstall yt-dlp` **会把 `/opt/homebrew/bin/yt-dlp` 一起删掉**
> （RECORD 里记着同一路径），卸完必须 `brew unlink yt-dlp && brew link yt-dlp` 补回来。

> ⬇️ **要下视频本体**（不是字幕）看 [`download.md`](download.md)——
> 那里有必须按编码筛 `avc1`、不能按 `ext=mp4` 筛的硬规则，按错了下出来的 mp4 播放器打不开。

### 获取视频元数据

```bash
yt-dlp --dump-json "URL"
```

### 下载字幕

```bash
# 下载字幕 (不下载视频)
yt-dlp --write-sub --write-auto-sub --sub-lang "zh-Hans,zh,en" --skip-download -o "/tmp/%(id)s" "URL"

# 然后读取 .vtt 文件
cat /tmp/VIDEO_ID.*.vtt
```

### 获取评论

```bash
# 提取评论（best-effort，不保证完整）
yt-dlp --write-comments --skip-download --write-info-json \
  --extractor-args "youtube:max_comments=20" \
  -o "/tmp/%(id)s" "URL"
# 评论在 .info.json 的 comments 字段中
```

### 搜索视频

```bash
yt-dlp --dump-json "ytsearch5:query"
```

> **字幕注意**: 手动上传的字幕提取可靠；自动生成字幕可能存在行间重复，需后处理。
> **评论注意**: `--write-comments` 基于网页抓取（非 YouTube Data API），部分评论可能丢失。

### 无字幕兜底：Whisper 音频转写

```bash
# 视频没有字幕时的兜底：下载音频并用 Whisper 转写（Groq 免费 key 即可）
agent-reach transcribe "https://www.youtube.com/watch?v=VIDEO_ID"
agent-reach transcribe ./local_audio.mp3 -o /tmp/transcript.txt
```

> 需要先配置 key：`agent-reach configure groq-key gsk_xxx`（免费，console.groq.com）
>
> 🔴 **大陆网络下 Groq 也必须挂代理**：直连 `api.groq.com` 必返 `HTTP 403 Forbidden`，与 key 是否有效无关。
> 🔴 `agent-reach doctor` 报 youtube `ok / 可转写音频（groq）` **不代表转录能跑通**——
> 它压根没探测 Groq 可达性，这是个误导性绿灯。正确用法（agent-reach 读环境变量代理）：
> ```bash
> HTTPS_PROXY=http://HOST:PORT HTTP_PROXY=http://HOST:PORT \
>   agent-reach transcribe ./audio.mp3 -o /tmp/transcript.txt
> ```
> agent-reach 只吐纯文本；要**带时间轴的 SRT**，直接打 Groq 要 `verbose_json` 再自行拼
> （key 在 `~/.agent-reach/config.yaml` 的 `groq_api_key`）。
> 或 `agent-reach configure openai-key sk-xxx`。默认 auto 模式：groq 失败自动降级 openai。

## B站 / Bilibili（bili-cli 为主，OpenCLI 补字幕）

> ⚠️ **不要用 yt-dlp 读 B站**：B站风控已全面 412 拦截 yt-dlp（实测最新版、直连/代理/带 Cookie 全部无效）。yt-dlp 只用于 YouTube。

### 视频详情/搜索/热门/排行 (bili-cli，只读无需登录)

```bash
# 视频详情（标题/UP主/时长/播放互动数据/字幕可用性）
bili video BVxxx

# 搜索视频
bili search "query" --type video -n 5

# 热门视频 / 排行榜
bili hot -n 10
bili rank -n 10

# 下载音频并切分为 ASR-ready WAV（无字幕时配合 agent-reach transcribe 转写）
bili audio BVxxx
```

### 字幕 (OpenCLI，需要桌面 Chrome)

```bash
# 字幕逐句带时间轴
opencli bilibili subtitle BVxxx

# OpenCLI 也能搜索/读视频元数据（备选）
opencli bilibili search "query" -f yaml
opencli bilibili video BVxxx -f yaml
```

### 零配置兜底：搜索 API 直连

```bash
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"
curl -s -c /tmp/bili_ck.txt -o /dev/null -A "$UA" "https://www.bilibili.com/"
curl -s -b /tmp/bili_ck.txt -A "$UA" -e "https://www.bilibili.com/" \
  "https://api.bilibili.com/x/web-interface/search/all/v2?keyword=QUERY&page=1"
```

> **安装 bili-cli**: `pipx install bilibili-cli`（上游 2026-03 起停更但实测健康；只读场景无需登录，`bili login` 扫码可解锁动态/收藏等个人功能）。

## 小宇宙播客 / Xiaoyuzhou Podcast

### 转录单集播客（可选 --polish 增强标点）

```bash
# 输出 Markdown 文件到 /tmp/。--polish 让 Llama 3.3 70B 给文稿补中文标点+合理分段
~/.agent-reach/tools/xiaoyuzhou/transcribe.sh --polish "https://www.xiaoyuzhoufm.com/episode/EPISODE_ID"
```

> 转写 prompt 已要求 Whisper 输出中文标点；若标点效果仍不理想，可加 `--polish` 用 Groq 上免费的 Llama 3.3 70B 补标点+合理分段（9 分钟播客约多 ~7 秒）。每次转写多一轮 LLM 调用，按需使用。

### 前置要求

1. **ffmpeg**: `brew install ffmpeg`
2. **Groq API Key** (免费): https://console.groq.com/keys
3. **配置 Key**: `agent-reach configure groq-key YOUR_KEY`
4. **首次运行**: `agent-reach install --env=auto` 安装工具

### 检查状态

```bash
agent-reach doctor
```

> 输出 Markdown 文件默认保存到 `/tmp/`。

## 选择指南

| 场景 | 推荐工具 |
|-----|---------|
| YouTube 字幕 | yt-dlp |
| B站视频详情/搜索 | bili-cli |
| B站字幕 | opencli bilibili subtitle |
| 播客转录 | 小宇宙 transcribe.sh |
| 无字幕音视频 | agent-reach transcribe（B站音频先 `bili audio`） |
