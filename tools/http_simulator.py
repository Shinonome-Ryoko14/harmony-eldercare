#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
居家守护 APP 联调用的 HTTP 模拟服务（无需硬件）。

实现与硬件网关一致的接口：
  GET /api/device/latest/?device_no=<n>&limit=<m>
  -> {"code":0,"latest":{...},"history":[...]}

用法：
  python3 http_simulator.py            # 监听 0.0.0.0:8000
  python3 http_simulator.py 8000       # 指定端口
然后在 APP 的「服务器设置」里填入本机局域网 IP 与端口，点「保存并重连」。
"""

import json
import random
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

# 简单内存存储：每个 device_no 一条历史，按 id 递增
_lock = threading.Lock()
_next_id = 1
_records = []  # [{"id","device_no","temp",...}]


def make_record(device_no):
    global _next_id
    with _lock:
        rec = {
            "id": _next_id,
            "device_no": device_no,
            "temp": round(random.uniform(20.0, 30.0), 1),
            "humi": round(random.uniform(35.0, 65.0), 1),
            "radar_presence": random.choice([0, 1]),
            "radar_motion": random.choice([0, 1]),
            "door1": random.choice([0, 0, 0, 1]),
            "sos": 0,
            "alarm": 0,
            "alarm_type": "",
            "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        }
        _next_id += 1
        _records.append(rec)
        if len(_records) > 500:
            del _records[:200]
        return rec


def producer():
    """每 5 秒产生一条新记录，模拟硬件周期上报。"""
    while True:
        make_record(0)
        time.sleep(5)


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send_json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urlparse(self.path)
        if parsed.path.rstrip("/") == "/api/device/latest":
            qs = parse_qs(parsed.query)
            device_no = int(qs.get("device_no", ["0"])[0])
            limit = int(qs.get("limit", ["10"])[0])
            with _lock:
                rows = [r for r in _records if r["device_no"] == device_no]
                latest = rows[-1] if rows else None
                history = list(reversed(rows[-limit:]))
            self._send_json({"code": 0, "latest": latest, "history": history})
            return
        if parsed.path in ("/", "/index.html"):
            page = "<h1>居家守护 模拟服务</h1><p>接口：/api/device/latest/?device_no=0&limit=10</p>"
            body = page.encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.send_error(404, "Not Found")

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    threading.Thread(target=producer, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"HTTP 模拟服务已启动: http://0.0.0.0:{port}/api/device/latest/?device_no=0&limit=10")
    print("按 Ctrl+C 退出")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
