#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""agent-reach-plus · 渠道补丁注入器

把本目录下的渠道源码（douyin.py / kuaishou.py）复制进已安装的
agent_reach.channels，并在 channels/__init__.py 里幂等注册。
`agent-reach` 升级/重装后重跑本脚本即可恢复。

用法:
    python3 apply.py            # 自动定位已安装的 agent_reach 并打补丁
"""
import importlib.util
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

# (源文件名, Channel 类名, 注册时插在哪个已有条目后面)
PATCHES = [
    ("douyin", "DouyinChannel", "XiaoHongShuChannel()"),
    ("kuaishou", "KuaishouChannel", "DouyinChannel()"),
]

# import 语句统一插在这个锚点后（上游 __init__.py 的最后一个原生 import）
IMPORT_ANCHOR = "from .xueqiu import XueqiuChannel"


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
    init = ch / "__init__.py"
    text = init.read_text(encoding="utf-8")
    changed = False

    for mod, cls, after_entry in PATCHES:
        src = HERE / f"{mod}.py"
        if not src.exists():
            print(f"⚠️  跳过 {mod}：{src} 不存在")
            continue

        # 1) 复制渠道源码
        dst = ch / f"{mod}.py"
        shutil.copyfile(src, dst)
        print(f"✅ 已写入 {dst}")

        # 2) 幂等注册 import
        import_line = f"from .{mod} import {cls}"
        if import_line not in text:
            if IMPORT_ANCHOR not in text:
                sys.exit(f"❌ 找不到 import 锚点：{IMPORT_ANCHOR}，上游结构可能已变，请人工处理")
            text = text.replace(IMPORT_ANCHOR, f"{IMPORT_ANCHOR}\n{import_line}", 1)
            changed = True

        # 3) 幂等注册实例（插在指定条目后面；条目不存在则挂到列表默认锚点）
        if f"{cls}()" not in text:
            anchor = f"    {after_entry},"
            if anchor not in text:
                anchor = "    XiaoHongShuChannel(),"
            if anchor not in text:
                sys.exit(f"❌ 找不到实例锚点：{after_entry}，上游结构可能已变，请人工处理")
            text = text.replace(anchor, f"{anchor}\n    {cls}(),", 1)
            changed = True

    if changed:
        init.write_text(text, encoding="utf-8")
        print(f"✅ 已更新 {init}")
    else:
        print("ℹ️  __init__.py 均已注册过，跳过")

    print("\n完成。验证：agent-reach doctor --json")


if __name__ == "__main__":
    main()
