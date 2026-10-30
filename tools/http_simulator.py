#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
居家守护 APP 联调用的 HTTP 模拟服务（无需硬件）。

接口：
  GET /api/device/latest/?device_no=<n>&limit=<m>
      -> {"code":0,"latest":{...},"history":[...]}
  GET /api/state                 -> 当前模拟状态
  GET /api/set?key=door1&value=1 -> 修改模拟状态（temp/humi/door1/radar_presence/...）
  GET /api/mode?legacy=1         -> 切换“旧字段名 / 时间戳”模式，用于验证 APP 兼容解析

用法：
  python3 http_simulator.py            # 监听 0.0.0.0:8000
  python3 http_simulator.py 8000       # 指定端口
然后在 APP 的「服务器设置」里填入本机局域网 IP 与端口，点「保存并重连」。
浏览器打开 http://<本机IP>:8000 可手动切换门磁、雷达、SOS、报警等状态。
"""

import json
import random
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

_lock = threading.Lock()
_next_id = 1
_records = []
_legacy = False

# 当前模拟状态（硬件某一时刻的采样值）
_state = {
    "temp": 25.0,
    "humi": 52.0,
    "radar_presence": 0,
    "radar_motion": 0,
    "door1": 1,
    "sos": 0,
    "alarm": 0,
    "alarm_type": "",
}


def build_record(device_no):
    """按当前状态生成一条记录"""
    global _next_id
    with _lock:
        now = datetime.now()
        rec = {
            "id": _next_id,
            "device_no": device_no,
            "temp": round(_state["temp"] + random.uniform(-0.4, 0.4), 1),
            "humi": round(_state["humi"] + random.uniform(-1.0, 1.0), 1),
            "radar_presence": _state["radar_presence"],
            "radar_motion": _state["radar_motion"],
            "door1": _state["door1"],
            "sos": _state["sos"],
            "alarm": _state["alarm"],
            "alarm_type": _state["alarm_type"],
            "created_at": now.strftime("%Y-%m-%d %H:%M:%S"),
            "epoch": int(now.timestamp()),
        }
        _next_id += 1
        _records.append(rec)
        if len(_records) > 500:
            del _records[:200]
        return rec


def to_wire(rec):
    """按当前模式输出给 APP，legacy 模式用于验证字段别名/时间戳解析"""
    if not _legacy:
        return {
            "id": rec["id"],
            "device_no": rec["device_no"],
            "temp": rec["temp"],
            "humi": rec["humi"],
            "radar_presence": rec["radar_presence"],
            "radar_motion": rec["radar_motion"],
            "door1": rec["door1"],
            "sos": rec["sos"],
            "alarm": rec["alarm"],
            "alarm_type": rec["alarm_type"],
            "created_at": rec["created_at"],
        }
    return {
        "id": rec["id"],
        "device": rec["device_no"],
        "temperature": rec["temp"],
        "humidity": rec["humi"],
        "presence": "有人" if rec["radar_presence"] else "无人",
        "motion": "开" if rec["radar_motion"] else "关",
        "door": "开" if not rec["door1"] else "关",
        "sos": rec["sos"],
        "alarm_status": rec["alarm"],
        "alarm_msg": rec["alarm_type"],
        "time": rec["epoch"],
    }


def producer():
    """每 5 秒产生一条新记录，模拟硬件周期上报。"""
    while True:
        build_record(0)
        time.sleep(5)


PAGE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>居家守护 · 模拟设备</title>
<style>
  body { font-family: -apple-system, "Segoe UI", sans-serif; margin: 0; padding: 16px; background: #f1f3f5; color: #1a1a1a; }
  h1 { font-size: 20px; margin: 0 0 4px; }
  .sub { color: #8a8a8a; font-size: 12px; margin-bottom: 16px; }
  .card { background: #fff; border-radius: 14px; padding: 14px; margin-bottom: 12px; }
  .row { display: flex; align-items: center; justify-content: space-between; padding: 6px 0; }
  .row span { font-size: 14px; }
  button { border: 0; border-radius: 8px; padding: 8px 14px; background: #26a69a; color: #fff; font-size: 13px; }
  button.off { background: #e0e0e0; color: #333; }
  input { border: 1px solid #ddd; border-radius: 8px; padding: 6px 8px; width: 80px; font-size: 14px; }
  code { background: #f5f5f5; padding: 2px 6px; border-radius: 4px; }
</style>
</head>
<body>
<h1>居家守护 · 模拟设备</h1>
<div class="sub">状态会立即写入下一条上报记录；APP 每 3 秒轮询一次。</div>

<div class="card">
  <div class="row"><span>温度 (℃)</span><input id="temp" type="number" step="0.1"></div>
  <div class="row"><span>湿度 (%)</span><input id="humi" type="number" step="1"></div>
  <div class="row"><span>门窗（0 开 / 1 关）</span><button id="door1">-</button></div>
  <div class="row"><span>雷达存在（1 有人 / 0 无人）</span><button id="radar_presence">-</button></div>
  <div class="row"><span>雷达运动（1 有 / 0 无）</span><button id="radar_motion">-</button></div>
  <div class="row"><span>SOS（1 求助 / 0 正常）</span><button id="sos">-</button></div>
  <div class="row"><span>报警（1 报警 / 0 正常）</span><button id="alarm">-</button></div>
</div>

<div class="card">
  <div class="row"><span>旧字段名 / 时间戳模式</span><button id="mode">-</button></div>
  <div class="sub" style="margin:0">开启后返回 temperature/humidity/presence/door/time(秒) 等字段，用于验证 APP 的兼容解析。</div>
</div>

<div class="card">
  <div class="sub" style="margin:0">接口：<code id="url"></code></div>
  <div class="sub" style="margin:8px 0 0">最新记录：<code id="latest">-</code></div>
</div>

<script>
let state = {};
let legacy = false;
const boolKeys = ["door1", "radar_presence", "radar_motion", "sos", "alarm"];

async function load() {
  const r = await fetch("/api/state");
  const j = await r.json();
  state = j.state;
  legacy = j.legacy;
  document.getElementById("temp").value = state.temp;
  document.getElementById("humi").value = state.humi;
  for (const k of boolKeys) {
    const b = document.getElementById(k);
    const on = state[k] === 1;
    b.textContent = on ? "1" : "0";
    b.className = on ? "" : "off";
  }
  const m = document.getElementById("mode");
  m.textContent = legacy ? "已开启" : "已关闭";
  m.className = legacy ? "" : "off";
  document.getElementById("url").textContent = location.origin + "/api/device/latest/?device_no=0&limit=10";
  document.getElementById("latest").textContent = j.latest ? JSON.stringify(j.latest) : "暂无";
}

async function setKey(k, v) {
  await fetch(`/api/set?key=${encodeURIComponent(k)}&value=${encodeURIComponent(v)}`);
  await load();
}

for (const k of boolKeys) {
  document.getElementById(k).onclick = () => setKey(k, state[k] === 1 ? 0 : 1);
}
document.getElementById("temp").onchange = (e) => setKey("temp", e.target.value);
document.getElementById("humi").onchange = (e) => setKey("humi", e.target.value);
document.getElementById("mode").onclick = async () => {
  await fetch(`/api/mode?legacy=${legacy ? 0 : 1}`);
  await load();
};
load();
setInterval(load, 2000);
</script>
</body>
</html>
"""


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _send_json(self, obj, status=200):
        body = json.dumps(obj, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _send_html(self, html, status=200):
        body = html.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        global _legacy
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        qs = parse_qs(parsed.query)

        if path == "/api/device/latest":
            device_no = int(qs.get("device_no", ["0"])[0])
            limit = int(qs.get("limit", ["10"])[0])
            with _lock:
                rows = [r for r in _records if r["device_no"] == device_no]
                latest = to_wire(rows[-1]) if rows else None
                history = [to_wire(r) for r in reversed(rows[-limit:])]
            self._send_json({"code": 0, "latest": latest, "history": history})
            return

        if path == "/api/state":
            with _lock:
                latest = to_wire(_records[-1]) if _records else None
                state = dict(_state)
            self._send_json({"code": 0, "state": state, "legacy": _legacy, "latest": latest})
            return

        if path == "/api/set":
            key = qs.get("key", [""])[0]
            value = qs.get("value", [""])[0]
            changed = False
            with _lock:
                if key in _state:
                    if key in ("temp", "humi"):
                        try:
                            _state[key] = float(value)
                            changed = True
                        except ValueError:
                            pass
                    else:
                        _state[key] = 1 if str(value).strip() in ("1", "true", "开", "是") else 0
                        changed = True
            if changed:
                # 立即生成一条新记录，APP 下一次轮询即可看到变化
                build_record(0)
            self._send_json({"code": 0, "state": _state})
            return

        if path == "/api/mode":
            with _lock:
                _legacy = qs.get("legacy", ["0"])[0] == "1"
            self._send_json({"code": 0, "legacy": _legacy})
            return

        if path == "/":
            self._send_html(PAGE)
            return
        self.send_error(404, "Not Found")

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    build_record(0)
    threading.Thread(target=producer, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"HTTP 模拟服务已启动: http://0.0.0.0:{port}")
    print(f"接口: http://0.0.0.0:{port}/api/device/latest/?device_no=0&limit=10")
    print(f"控制台: http://127.0.0.1:{port}/")
    print("按 Ctrl+C 退出")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        server.shutdown()


if __name__ == "__main__":
    main()
