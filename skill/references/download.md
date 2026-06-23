# 下载视频/图文到本地（按链接平台自动选工具）

用户丢一个链接 + 说「下视频 / 下下来 / 帮我下载这个 / 下到本地（桌面）」时：**认出平台 → 用对应工具下到本地**（默认下用户指定目录，没指定就当前目录或 `~/Desktop`）。动手前可 `agent-reach doctor --json` 确认相关后端就绪。

> 这是「获取媒体文件」的能力，区别于其他 references 的「取文字内容做调研」。

## YouTube（yt-dlp，免登录，画质不锁）

```bash
yt-dlp -f "bv*[height<=1080][ext=mp4]+ba/b" --merge-output-format mp4 -o "out.%(ext)s" "URL"
# 要最高画质：去掉 [height<=1080] 限制
```

## B站（BBDown；⚠️禁用 yt-dlp——B站 412 拦截）

```bash
"$HOME/.agent-reach/bin/BBDown" "BV号或URL" --work-dir DIR
```
- `install.sh` 已把 BBDown 便携版装到 `~/.agent-reach/bin/`；合流需要系统装了 **ffmpeg**。
- 游客只能下 480P；**1080P+ 需登录态**：先 `agent-reach configure --from-browser chrome`（提取 B站 SESSDATA）。
- 若 `~/.agent-reach/bin/BBDown` 不存在：按平台从 https://github.com/nilaoda/BBDown/releases 拉对应便携包临时用。

## 小红书（OpenCLI，要 Chrome 登录小红书）

```bash
opencli xiaohongshu download "<带 xsec_token 的笔记完整URL>" --output DIR
```
- 图文笔记下全部图，视频笔记下 mp4，无水印。URL 从 `opencli xiaohongshu search` 结果取（含 xsec_token）。

## 抖音（两法，都先抓分享页拿 sec_uid / aweme_id）

```bash
# 拿 aweme_id：
curl -sIL "https://v.douyin.com/XXXX/" -A "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0)" | grep -i "^location"   # 抠 /video/(数字)
# 拿作者 sec_uid：
curl -s "https://www.iesdouyin.com/share/video/<aweme_id>/?from_ssr=1" -A "Mozilla/5.0 (iPhone; CPU iPhone OS 16_0) AppleWebKit/605.1.15" \
  | grep -oE "MS4wLjABAAAA[A-Za-z0-9_-]{20,}" | sort -u
```

**A 首选（画质高到 1080p，要 Chrome 登录抖音）：**
```bash
opencli douyin user-videos "<真sec_uid>" --limit 20 -f json    # 找到目标 aweme 的 play_url
curl -L "<play_url>" -H "Referer: https://www.douyin.com/" -o out.mp4
```
> ⚠️ `user-videos` 传**数字 uid 会回退成你自己的号**，必须传**真 sec_uid**（`MS4wLjABAAAA…`）。

**B 兜底（免登录、不用 opencli，720p）：**
解析上面分享页的 `window._ROUTER_DATA` JSON → 递归找 `play_addr.url_list[0]`（形如 `aweme.snssdk.com/aweme/v1/playwm/?video_id=...`）→ 把 `playwm` 改 `play` 去水印 → `curl -L "<url>" -A "<移动UA>" -H "Referer: https://www.douyin.com/" -o out.mp4`。

> 选择：要高画质走 A（需登录）；图省事/没登录走 B（720p）。yt-dlp 抖音解析器已过期，别用。

## 整个作者批量下载

- **抖音**：`opencli douyin user-videos "<真sec_uid>" --limit 20 -f json` 一次返回该作者作品（每条带 play_url），循环 curl，统一放一个文件夹（文件名用序号+标题）。
- **小红书**：逐条 note URL 调 `download`。

## 合规（务必遵守）

仅限**个人自用**。🔴 禁止批量搬运、去水印二次发布、商用；作者设「禁止下载」的内容，技术能取 ≠ 可以使用。OpenCLI 类（小红书/抖音）用你本人真实登录态，Chrome 要开着。
