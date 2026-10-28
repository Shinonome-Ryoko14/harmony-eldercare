#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
居家守护 APP 的 AI 联调 Mock 服务（OpenAI 兼容）。

用途：
  1) 没有申请到免费模型 Key 时，验证 APP 的流式/非流式、上下文拼装、错误处理；
  2) 比赛现场没有外网时，用本机模拟大模型回答。

启动：
  python3 tools/ai_mock_server.py          # 监听 0.0.0.0:8001
  python3 tools/ai_mock_server.py 8001

APP 配置：
  设置 -> AI 管家模型 -> 自定义
  Base URL : http://<电脑局域网IP>:8001/v1
  模型名   : mock-care
  API Key  : 任意非空字符串（例如 test）

接口：
  POST /v1/chat/completions   OpenAI 兼容（支持 stream=true）
  GET  /v1/models             模型列表
  GET  /                     简单说明页
"""

import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MODEL_NAME = "mock-care"


def build_answer(body):
    """根据用户问题拼一段带业务上下文的演示回答。"""
    messages = body.get("messages", [])
    user_text = ""
    context = ""
    for item in messages:
        role = item.get("role", "")
        content = item.get("content", "")
        if role == "user":
            user_text = content
        elif role == "system":
            context = content

    question = user_text.strip() or "今天老人情况怎么样？"

    if "告警" in question or "告警" in context and "解读" in question:
        return (
            "【风险判断】\n"
            "这条告警需要优先确认现场情况，尤其是涉及 SOS、设备报警或长时间无活动时。\n\n"
            "【建议步骤】\n"
            "1. 先拨打老人电话，确认意识与行动状态；\n"
            "2. 电话无人接听时，联系邻居、社区网格员或家属上门查看；\n"
            "3. 确认是误报后，在告警页填写处置结果；若老人身体不适，立即拨打 120。\n\n"
            "【是否需要联系家属】\n"
            "建议同步通知主要监护人，并在安全日志中记录处置过程。\n\n"
            "（本回答来自本地 Mock 模型，仅用于联调演示）"
        )

    if "家属" in question or "通知" in question:
        return (
            "【家属通知】\n"
            "今天老人的居家状态整体平稳：室内温湿度正常，门窗已关闭，雷达检测到日常活动。\n"
            "今日活动次数与昨日接近，暂无明显下降。近期没有新的紧急告警。\n"
            "建议晚间再电话问候一次，确认进食和用药情况。\n\n"
            "（本回答来自本地 Mock 模型，仅用于联调演示）"
        )

    return (
        "【今日情况】\n"
        "设备在线，室内温度约 25℃，湿度约 52%，门窗关闭，雷达检测到日常活动。\n"
        "今日活动次数与昨日基本持平，最近没有新的紧急告警。\n\n"
        "【建议】\n"
        "1. 保持日常电话问候，关注进食、睡眠和用药；\n"
        "2. 若活动量持续下降或出现设备离线，请及时联系上门查看；\n"
        "3. 紧急情况请立即拨打 120。\n\n"
        "（本回答来自本地 Mock 模型，仅用于联调演示）"
    )


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        sys.stderr.write("[ai-mock] " + (fmt % args) + "\n")

    def _json(self, code, payload):
        data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path.startswith("/v1/models"):
            self._json(200, {
                "object": "list",
                "data": [{"id": MODEL_NAME, "object": "model", "owned_by": "local-mock"}]
            })
            return
        text = (
            "居家守护 AI Mock 服务已启动。\n"
            "Base URL: http://<本机IP>:8001/v1\n"
            f"模型名: {MODEL_NAME}\n"
            "API Key: 任意非空字符串\n"
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(text)))
        self.end_headers()
        self.wfile.write(text)

    def do_POST(self):
        if not self.path.startswith("/v1/chat/completions"):
            self._json(404, {"error": {"message": "not found"}})
            return

        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            body = json.loads(raw.decode("utf-8"))
        except Exception:
            self._json(400, {"error": {"message": "invalid json"}})
            return

        answer = build_answer(body)
        stream = bool(body.get("stream", False))

        if not stream:
            self._json(200, {
                "id": "chatcmpl-mock",
                "object": "chat.completion",
                "created": int(time.time()),
                "model": MODEL_NAME,
                "choices": [{
                    "index": 0,
                    "message": {"role": "assistant", "content": answer},
                    "finish_reason": "stop"
                }],
                "usage": {"prompt_tokens": 100, "completion_tokens": 100, "total_tokens": 200}
            })
            return

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()

        # 按 6 个字符一片推送，模拟真实模型的逐字输出
        step = 6
        for i in range(0, len(answer), step):
            piece = answer[i:i + step]
            chunk = {
                "id": "chatcmpl-mock",
                "object": "chat.completion.chunk",
                "created": int(time.time()),
                "model": MODEL_NAME,
                "choices": [{
                    "index": 0,
                    "delta": {"content": piece},
                    "finish_reason": None
                }]
            }
            line = "data: " + json.dumps(chunk, ensure_ascii=False) + "\n\n"
            self.wfile.write(line.encode("utf-8"))
            self.wfile.flush()
            time.sleep(0.03)

        done = {
            "id": "chatcmpl-mock",
            "object": "chat.completion.chunk",
            "created": int(time.time()),
            "model": MODEL_NAME,
            "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}]
        }
        self.wfile.write(("data: " + json.dumps(done, ensure_ascii=False) + "\n\n").encode("utf-8"))
        self.wfile.write(b"data: [DONE]\n\n")
        self.wfile.flush()
        self.close_connection = True


def main():
    port = 8001
    if len(sys.argv) > 1:
        port = int(sys.argv[1])
    server = ThreadingHTTPServer(("0.0.0.0", port), Handler)
    print(f"AI Mock 已启动: http://0.0.0.0:{port}/v1  (模型名: {MODEL_NAME})")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n已停止")


if __name__ == "__main__":
    main()
