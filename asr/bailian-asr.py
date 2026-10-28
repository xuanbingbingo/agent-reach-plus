#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""bailian-asr · 阿里云百炼录音文件转写（默认 paraformer-v2，大陆直连）

本地音频/视频 → 文字。流程：ffmpeg 压成 16k 单声道 mp3 → 传到百炼临时存储
（免自备 OSS，48 小时自动删）→ 异步提交转写 → 轮询 → 取结果。
单文件最长 12 小时，不用切段。只依赖 Python 标准库 + ffmpeg。

模型（新用户各送 10 小时）：
  paraformer-v2  ¥0.00008/秒 ≈ 0.29 元/小时  默认（2026-10-28 用户定）；英文专名偶尔听错（Claude Code→cloud code）
  fun-asr        ¥0.00022/秒 ≈ 0.79 元/小时  中英混杂更准，需要时 --model fun-asr

用法:
    bailian-asr <音频或视频文件> [-o 输出] [--format text|srt|json] [--model paraformer-v2|fun-asr]

Key 读取顺序：环境变量 DASHSCOPE_API_KEY > ~/.agent-reach/config.yaml 的 dashscope_api_key
退出码：0 成功；2 缺 key / 参数错；3 上传失败；4 转写失败
"""
import argparse
import json
import mimetypes
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

API = "https://dashscope.aliyuncs.com/api/v1"
CONFIG = Path.home() / ".agent-reach" / "config.yaml"
# 大陆直连，不吃 shell 里继承的 HTTPS_PROXY
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


def log(msg):
    print(msg, file=sys.stderr, flush=True)


def load_key():
    key = os.environ.get("DASHSCOPE_API_KEY", "").strip()
    if key:
        return key
    if CONFIG.is_file():
        # 不依赖 PyYAML：config.yaml 是平铺的 key: value
        for line in CONFIG.read_text(encoding="utf-8").splitlines():
            m = re.match(r"\s*dashscope_api_key\s*:\s*['\"]?([^'\"\s#]+)", line)
            if m:
                return m.group(1)
    return ""


def http(method, url, key=None, body=None, headers=None, timeout=60):
    h = dict(headers or {})
    if key:
        h["Authorization"] = f"Bearer {key}"
    if isinstance(body, (dict, list)):
        body = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=h, method=method)
    try:
        with OPENER.open(req, timeout=timeout) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


def to_mp3(src, work):
    if not shutil.which("ffmpeg"):
        log("❌ 缺 ffmpeg"); sys.exit(2)
    dst = Path(work) / f"{uuid.uuid4().hex}.mp3"
    p = subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", str(src), "-vn",
                        "-ac", "1", "-ar", "16000", "-b:a", "48k", str(dst)],
                       capture_output=True, text=True)
    if p.returncode != 0 or not dst.exists():
        log(f"❌ ffmpeg 转码失败: {p.stderr.strip()[:300]}"); sys.exit(2)
    return dst


def upload(key, path, model):
    """传到百炼临时存储，返回 oss:// 地址。"""
    code, raw = http("GET", f"{API}/uploads?action=getPolicy&model={model}", key)
    if code != 200:
        log(f"❌ 取上传凭证失败 HTTP {code}: {raw[:200].decode(errors='replace')}"); sys.exit(3)
    d = json.loads(raw)["data"]
    obj = f"{d['upload_dir']}/{path.name}"
    fields = {
        "OSSAccessKeyId": d["oss_access_key_id"],
        "Signature": d["signature"],
        "policy": d["policy"],
        "key": obj,
        "x-oss-object-acl": d["x_oss_object_acl"],
        "x-oss-forbid-overwrite": d["x_oss_forbid_overwrite"],
        "success_action_status": "200",
    }
    boundary = uuid.uuid4().hex
    parts = []
    for k, v in fields.items():
        parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode())
    ctype = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    parts.append(f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="{path.name}"\r\n'
                 f"Content-Type: {ctype}\r\n\r\n".encode())
    parts.append(path.read_bytes())
    parts.append(f"\r\n--{boundary}--\r\n".encode())
    code, raw = http("POST", d["upload_host"], body=b"".join(parts),
                     headers={"Content-Type": f"multipart/form-data; boundary={boundary}"}, timeout=600)
    if code != 200:
        log(f"❌ 上传失败 HTTP {code}: {raw[:200].decode(errors='replace')}"); sys.exit(3)
    return f"oss://{obj}"


def transcribe(key, oss_url, model, timeout):
    body = {"model": model, "input": {"file_urls": [oss_url]},
            "parameters": {"language_hints": ["zh", "en"]}}
    code, raw = http("POST", f"{API}/services/audio/asr/transcription", key, body,
                     {"X-DashScope-Async": "enable", "X-DashScope-OssResourceResolve": "enable"})
    if code != 200:
        log(f"❌ 提交失败 HTTP {code}: {raw[:300].decode(errors='replace')}"); sys.exit(4)
    task = json.loads(raw)["output"]["task_id"]
    deadline = time.time() + timeout
    while time.time() < deadline:
        time.sleep(2)
        code, raw = http("GET", f"{API}/tasks/{task}", key)
        if code != 200:
            continue
        out = json.loads(raw)["output"]
        st = out.get("task_status")
        if st == "SUCCEEDED":
            r = out["results"][0]
            if r.get("subtask_status") != "SUCCEEDED":
                log(f"❌ 转写失败: {r.get('code')} {r.get('message')}"); sys.exit(4)
            code, raw = http("GET", r["transcription_url"], timeout=120)
            return json.loads(raw)
        if st in ("FAILED", "CANCELED", "UNKNOWN"):
            log(f"❌ 转写失败: {out.get('code')} {out.get('message')}"); sys.exit(4)
    log(f"❌ 转写超时（{timeout}s），任务 {task}"); sys.exit(4)


def srt_time(ms):
    h, ms = divmod(int(ms), 3600000)
    m, ms = divmod(ms, 60000)
    s, ms = divmod(ms, 1000)
    return f"{h:02}:{m:02}:{s:02},{ms:03}"


def render(result, fmt):
    sents = [s for t in result.get("transcripts", []) for s in t.get("sentences", [])]
    if fmt == "json":
        return json.dumps(result, ensure_ascii=False, indent=2)
    if fmt == "srt":
        return "\n".join(f"{i}\n{srt_time(s['begin_time'])} --> {srt_time(s['end_time'])}\n{s['text'].strip()}\n"
                         for i, s in enumerate(sents, 1))
    # text：句间停顿超过 1.5 秒另起一段，其余连成一段
    paras, cur, last_end = [], "", None
    for s in sents:
        if cur and last_end is not None and s["begin_time"] - last_end > 1500:
            paras.append(cur); cur = ""
        cur += s["text"].strip()
        last_end = s["end_time"]
    if cur:
        paras.append(cur)
    return "\n".join(paras)


def main():
    ap = argparse.ArgumentParser(description="阿里云百炼录音文件转写")
    ap.add_argument("source", help="本地音频或视频文件")
    ap.add_argument("-o", "--output", help="写到文件（默认打印到 stdout）")
    ap.add_argument("--format", choices=["text", "srt", "json"], default="text")
    ap.add_argument("--model", default=os.environ.get("BAILIAN_ASR_MODEL", "paraformer-v2"))
    ap.add_argument("--timeout", type=int, default=1800, help="等结果的最长秒数")
    a = ap.parse_args()

    src = Path(a.source).expanduser()
    if not src.is_file():
        log(f"❌ 文件不存在: {src}"); sys.exit(2)
    key = load_key()
    if not key:
        log("❌ 没有百炼 key：设 DASHSCOPE_API_KEY，或在 ~/.agent-reach/config.yaml 写 dashscope_api_key: sk-xxx")
        sys.exit(2)

    with tempfile.TemporaryDirectory(prefix="bailian-asr-") as work:
        mp3 = to_mp3(src, work)
        log(f"   [百炼 {a.model}] 上传 {mp3.stat().st_size // 1024}KB …")
        oss = upload(key, mp3, a.model)
        log(f"   [百炼 {a.model}] 转写中 …")
        result = transcribe(key, oss, a.model, a.timeout)

    text = render(result, a.format)
    if not text.strip():
        log("❌ 转写结果为空"); sys.exit(4)
    if a.output:
        Path(a.output).write_text(text + "\n", encoding="utf-8")
        log(f"   ✅ 已写入 {a.output}（{len(text)} 字）")
    else:
        print(text)


if __name__ == "__main__":
    main()
