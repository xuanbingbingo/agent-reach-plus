#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""agent-reach-plus · 抖音渠道补丁注入器

把 douyin.py 复制进已安装的 agent_reach.channels，并在 channels/__init__.py
里幂等注册 DouyinChannel。`agent-reach` 升级/重装后重跑本脚本即可恢复。

用法:
    python3 apply.py            # 自动定位已安装的 agent_reach 并打补丁
"""
import importlib.util
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def find_channels_dir() -> Path:
    spec = importlib.util.find_spec("agent_reach")
    if not spec or not spec.origin:
        sys.exit("❌ 没找到已安装的 agent_reach。先 `pipx install agent-reach`。")
    ch = Path(spec.origin).parent / "channels"
    if not ch.is_dir():
        sys.exit(f"❌ channels 目录不存在: {ch}")
    return ch


def main():
    ch = find_channels_dir()

    # 1) 复制渠道源码
    dst = ch / "douyin.py"
    shutil.copyfile(HERE / "douyin.py", dst)
    print(f"✅ 已写入 {dst}")

    # 2) 幂等注册到 __init__.py
    init = ch / "__init__.py"
    text = init.read_text(encoding="utf-8")
    changed = False

    if "from .douyin import DouyinChannel" not in text:
        text = text.replace(
            "from .xueqiu import XueqiuChannel",
            "from .xueqiu import XueqiuChannel\nfrom .douyin import DouyinChannel",
            1,
        )
        changed = True

    if "DouyinChannel()" not in text:
        text = text.replace(
            "    XiaoHongShuChannel(),",
            "    XiaoHongShuChannel(),\n    DouyinChannel(),",
            1,
        )
        changed = True

    if changed:
        init.write_text(text, encoding="utf-8")
        print(f"✅ 已在 {init.name} 注册 DouyinChannel")
    else:
        print("ℹ️  __init__.py 已注册过，跳过")

    print("\n完成。验证：agent-reach doctor --json | grep douyin")


if __name__ == "__main__":
    main()
