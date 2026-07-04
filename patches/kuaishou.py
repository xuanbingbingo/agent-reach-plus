# -*- coding: utf-8 -*-
"""Kuaishou (快手) — OpenCLI browser 后端。

快手没有 OpenCLI 原生 adapter，走 `opencli browser` 通用浏览器桥：
开一个 kuaishou.com 的标签页，在页面上下文里 fetch 快手网页版自己的
GraphQL 接口（cookie 由浏览器自动携带，全部 HttpOnly）。因此和抖音
一样需要桌面 Chrome + 已登录 kuaishou.com。

提供的能力（完整命令与 GraphQL 查询体在 references/social.md）：
  - visionSearchPhoto        关键词搜视频（20条/页，pcursor 翻页）
  - visionVideoDetail        单视频详情（photoId → 标题/时长/photoUrl）
  - visionProfilePhotoList   某用户作品列表（userId → 作品+photoUrl）

已实测的三条硬规则（2026-07，详见 references/social.md 快手节）：
  1. GraphQL 必须提交完整 fragment 查询体，精简查询直接返回空
  2. cookie 全 HttpOnly，document.cookie 判不了登录态——以接口
     result==1 且 feeds 非空为准
  3. photoUrl 是 CDN 直链，裸 curl 可下载（带 UA+Referer 即可，
     无需 cookie），比抖音宽松；下载路径见 references/download.md
"""

from .base import Channel


class KuaishouChannel(Channel):
    name = "kuaishou"
    description = "快手视频和搜索"
    backends = ["OpenCLI browser"]
    tier = 2  # 需要桌面 Chrome + 登录快手

    def can_handle(self, url: str) -> bool:
        from urllib.parse import urlparse

        d = urlparse(url).netloc.lower()
        return (
            "kuaishou.com" in d       # www.kuaishou.com / v.kuaishou.com 短链
            or "chenzhongtech.com" in d  # 快手分享落地页域名
            or "gifshow.com" in d     # 快手老域名，部分分享链仍在用
        )

    def check(self, config=None):
        """复用 OpenCLI 探活；登录态由用户在 Chrome 里自行维护。"""
        from agent_reach.backends import opencli_status

        self.active_backend = None
        st = opencli_status()

        if not st.installed:
            return "off", (
                "未安装 OpenCLI（快手后端）。安装：\n"
                "  agent-reach install --channels opencli\n"
                "  装好后保持 Chrome 打开并登录 https://www.kuaishou.com"
            )
        if st.broken:
            return "error", st.hint
        if st.ready:
            self.active_backend = "OpenCLI browser"
            return "ok", (
                "OpenCLI browser 可用（复用浏览器登录态）。用法："
                "opencli browser ks open kuaishou.com 后在页面上下文 "
                "fetch GraphQL（visionSearchPhoto/visionVideoDetail/"
                "visionProfilePhotoList），查询体见 references/social.md；"
                "下载走 photoUrl 直链 curl"
            )
        return "warn", st.hint
