# 下载视频/图文到本地（按链接平台自动选工具）

用户丢一个链接 + 说「下视频 / 下下来 / 帮我下载这个 / 下到本地（桌面）」时：**认出平台 → 用对应工具下到本地**（默认下用户指定目录，没指定就当前目录或 `~/Desktop`）。动手前可 `agent-reach doctor --json` 确认相关后端就绪。

> 这是「获取媒体文件」的能力，区别于其他 references 的「取文字内容做调研」。

## YouTube（yt-dlp，免登录，画质不锁）

```bash
yt-dlp --no-playlist \
  -f "bv*[vcodec^=avc1]+ba[acodec^=mp4a]/b[vcodec^=avc1]" \
  --merge-output-format mp4 -o "%(title).80s.%(ext)s" "URL"
```

> 🔴 **按编码筛（`vcodec^=avc1`），不要按后缀筛（`ext=mp4`）。**
> `.mp4` 只是容器：YouTube 同一条视频并行提供 H.264(avc1) / VP9 / AV1 三套视频轨，
> **VP9 和 AV1 的轨也封在 mp4 容器里**，所以 `ext=mp4` 筛不干净——实测会选中
> `616(vp9)+251(opus)` 或 `398(av1)+251(opus)` 这类组合，下出来的 `.mp4`
> 在 macOS QuickTime / 预览、Windows 照片、剪映里**双击打不开或黑屏没声**（它们只解 H.264/HEVC + AAC）。
> 判据：下完跑一句 `ffprobe -v error -show_entries stream=codec_name -of csv=p=0 out.mp4`，
> **必须是 `h264` + `aac`**；看到 vp9 / av1 / opus 就是选错轨，**重下，别转码**。

- 体积变大是正常的：AV1/VP9 压缩率高于 H.264，同画质文件更小；换成 H.264 体积必涨，
  但**画质无损**（都是从源直接取轨，全程没有转码）。
- 限高画质写 `bv*[vcodec^=avc1][height<=1080]`；要最高画质就别加 height 条件。
- 拿不准有哪些轨，先列一遍 `yt-dlp -F "URL"` 找 `avc1` 行
  （1080p 常见是 `137`，720p 是 `136`，AAC 音轨是 `140`）。
- 部分视频只有低分辨率的 avc1 轨（Shorts 常见 720p 封顶），这不是漏下，是源上就没有。
- 🔴 **大陆网络需自备 HTTP 代理**：youtube.com / googlevideo.com 直连不可达，
  且命令行工具不读系统代理开关，必须显式 `--proxy http://HOST:PORT`
  （端口填你自己代理客户端的，本文不写死）。嫌每次都要加，就写进 `~/.config/yt-dlp/config`：
  ```
  --proxy http://127.0.0.1:7890
  ```
- 过程中报 `SSL: UNEXPECTED_EOF_WHILE_READING` 一般是代理节点抖动，yt-dlp 会自行重试，不影响成片完整性。

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

## 抖音（⭐主路径=分享页直抠 play_url，不绕 sec_uid）

> **为什么不走 sec_uid + user-videos 当主路径**（实测 2026-06-23 踩坑）：
> - 分享页 DOM 里 `MS4wLjABAAAA…` 串一大堆，但**不全是作者**：①重定向 URL 自带的 `did=`/`iid=` 是设备号/安装号，同格式；②页面底部「相关推荐」位挂一排别人的视频+头像，各带各自作者 sec_uid。「抠第一个」经常拿到设备号或推荐位别人的号。
> - 就算 sec_uid 抠对，`user-videos` 默认只返回最近 ~14 条，目标视频稍早就命中不到。
> 结论：分享页 HTML 本身就含 `douyinvod` 播放链接，且带 `__vid=<aweme_id>` 可精确校验——直接抠它，不用猜作者、不受分页限制。

```bash
# 第1步 拿 aweme_id：只读重定向头，curl 仍可用
curl -sIL "https://v.douyin.com/XXXX/" | grep -i "^location"   # 抠 /share/video/(数字)

# 第2步 打开 iesdouyin 分享页（需 Chrome 开着+登录抖音，等 ~2s 渲染）
opencli browser dy open "https://www.iesdouyin.com/share/video/<aweme_id>/?from_ssr=1"

# 第3步 ⭐直抠：从页面 HTML grep douyinvod 链接，自带 __vid 校验是不是这条视频
opencli browser dy eval "(()=>{var h=document.documentElement.outerHTML;var m=h.match(/https?:[^\"'\\\\ ]*douyinvod[^\"'\\\\ ]*/g)||[];return JSON.stringify(m.filter(u=>u.indexOf('__vid=<aweme_id>')>-1).slice(0,2));})()"
#   抠不到时再看 video 元素：document.querySelector('video').src / .currentSrc

# 第4步 解码 &amp;→& 后下载（play_url 带时效签名+地区锁，过期/SSL报错就重取一次）
curl -L -H "Referer: https://www.douyin.com/" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15" "<play_url>" -o ~/Desktop/标题.mp4
```
> ⚠️ **不要裸 curl iesdouyin 分享页**：抖音风控经常把裸 curl 返回成 0 字节（时好时坏），统一走 `opencli browser open` + eval。
> ⚠️ 别用 `douyin.com/video/<id>` 页——推荐位污染更重；必须用 **iesdouyin 分享页**。

**兜底 A（主路径第3步抠不到 douyinvod、页面没渲出 video 时才用）：sec_uid → user-videos**
```bash
# 先抠候选 sec_uid（去重取前几个），逐个试 user-videos 找目标 aweme_id 命中
opencli browser dy eval "(()=>{var h=document.documentElement.outerHTML;var s=(h.match(/MS4wLjABAAAA[A-Za-z0-9_-]{20,}/g)||[]);return JSON.stringify(s.filter((v,i,a)=>a.indexOf(v)===i).slice(0,4));})()"
opencli douyin user-videos "<真sec_uid>" --limit 20 -f json    # 按 aweme_id 命中取 play_url；对不上换下一个候选
curl -L "<play_url>" -H "Referer: https://www.douyin.com/" -o out.mp4
```
> ⚠️ `user-videos` 传**数字 uid 会回退成你自己的号**，必须传**真 sec_uid**（`MS4wLjABAAAA…`）。

**兜底 B（免登录、720p）：** 解析分享页 `window._ROUTER_DATA` → 递归找 `play_addr.url_list[0]`（`aweme.snssdk.com/aweme/v1/playwm/?video_id=...`）→ `playwm` 改 `play` 去水印 → curl（带移动 UA + Referer）。

> yt-dlp 抖音解析器已过期，别用。

## 快手（GraphQL 拿 photoUrl 直链 → 裸 curl，比抖音宽松）

> 实测 2026-07：`photoUrl` 是 kwaicdn CDN 直链，**裸 curl 就能下**（带 UA+Referer 即可，无需 cookie）。拿 photoUrl 那一步需要 Chrome 开着+登录快手（GraphQL 跑法详见 [`social.md`](social.md) 快手节）。

```bash
# 第1步 拿 photoId：链接是 kuaishou.com/short-video/<photoId> 直接抠；
#        v.kuaishou.com 短链先解析重定向
curl -sIL "https://v.kuaishou.com/XXXX" | grep -i "^location"

# 第2步 GraphQL visionVideoDetail 拿 photoUrl（完整查询体在 social.md 快手节，🔴必须完整 fragment）
opencli browser ks open "https://www.kuaishou.com"
#   ... eval fetch visionVideoDetail(photoId) → photo.photoUrl

# 第3步 直链下载（URL 含 & 等符号，务必整体加引号）
curl -L -H "Referer: https://www.kuaishou.com/" -H "User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36" "<photoUrl>" -o ~/Desktop/标题.mp4
```

> ⚠️ curl 若报 exit 7 / 连不上，先检查 shell 里有没有残留 HTTP(S)_PROXY 代理变量（`env -u HTTP_PROXY -u HTTPS_PROXY curl ...` 绕开）。
> ⚠️ photoUrl 带时效签名，过期就回第2步重取一次。
> ⚠️ yt-dlp 没有可用的快手解析器，别试。

## 整个作者批量下载

- **抖音**：`opencli douyin user-videos "<真sec_uid>" --limit 20 -f json` 一次返回该作者作品（每条带 play_url），循环 curl，统一放一个文件夹（文件名用序号+标题）。
- **快手**：GraphQL `visionProfilePhotoList(userId)` 翻页收集每条的 `photoUrl`（查询体见 [`social.md`](social.md)），循环 curl，间隔 2-3 秒。
- **小红书**：逐条 note URL 调 `download`。

## 合规（务必遵守）

仅限**个人自用**。🔴 禁止批量搬运、去水印二次发布、商用；作者设「禁止下载」的内容，技术能取 ≠ 可以使用。OpenCLI 类（小红书/抖音/快手）用你本人真实登录态，Chrome 要开着。
