# -*- coding: utf-8 -*-
"""Douyin (抖音) — OpenCLI backend.

抖音通过 OpenCLI 的浏览器桥接复用桌面 Chrome 的登录态访问，因此和小红书一样
需要桌面 Chrome + 已登录 douyin.com。OpenCLI 在服务器（无桌面浏览器）上不会
探活成功，符合预期。

提供的能力（命令在 references/social.md）：
  - opencli douyin search "<关键词>"        关键词搜视频
  - opencli douyin user-videos <sec_uid>    某用户作品列表（含 play_url 下载直链）
  - opencli douyin hashtag / stats / ...     话题/作品数据

注意：play_url 是 web 播放版（已转码，无水印），不是作者上传的原始母带。
"""

from .base import Channel


class DouyinChannel(Channel):
    name = "douyin"
    description = "抖音视频和搜索"
    backends = ["OpenCLI"]
    tier = 2  # 需要桌面 Chrome + 登录抖音

    def can_handle(self, url: str) -> bool:
        from urllib.parse import urlparse

        d = urlparse(url).netloc.lower()
        return (
            "douyin.com" in d
            or "iesdouyin.com" in d
            or "v.douyin.com" in d
        )

    def check(self, config=None):
        """复用 OpenCLI 探活；登录态由用户在 Chrome 里自行维护。"""
        from agent_reach.backends import opencli_status

        self.active_backend = None
        st = opencli_status()

        if not st.installed:
            return "off", (
                "未安装 OpenCLI（抖音后端）。安装：\n"
                "  agent-reach install --channels opencli\n"
                "  装好后保持 Chrome 打开并登录 https://www.douyin.com"
            )
        if st.broken:
            return "error", st.hint
        if st.ready:
            self.active_backend = "OpenCLI"
            return "ok", (
                "OpenCLI 可用（复用浏览器登录态）。用法："
                "opencli douyin search/user-videos/hashtag -f yaml；"
                "下载走 user-videos 返回的 play_url"
            )
        return "warn", st.hint
