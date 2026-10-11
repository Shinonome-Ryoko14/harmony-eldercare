#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
硬件 UDP 模拟器（联调用）。

用法：
    python3 tools/udp_simulator.py                 # 监听 8888，收到探测包即回复
    python3 tools/udp_simulator.py --interval 2    # 每 2 秒主动广播一次数据
    python3 tools/udp_simulator.py --sos           # 模拟一次 SOS 告警后退出

APP 每 3 秒向 255.255.255.255:8888 广播探测包 "ELDER_CARE_DISCOVER"，
本脚本收到后把当前模拟数据回发到来源 IP/端口。
"""
import argparse
import json
import random
import socket
import time

PROBE = b"ELDER_CARE_DISCOVER"
PORT = 8888


class Simulator:
    def __init__(self):
        self.temp = 26.5
        self.humi = 45
        self.magnet = 0          # 0 关 1 开
        self.pulse = 0           # 0 无活动 1 有活动
        self.total = 0           # 累计活动次数
        self.sos = 0             # 0 正常 1 求助

    def step(self):
        """随机演化一次状态，便于观察页面变化。"""
        self.temp = round(min(34, max(18, self.temp + random.uniform(-0.4, 0.4))), 1)
        self.humi = int(min(80, max(30, self.humi + random.randint(-2, 2))))
        # 20% 概率发生活动
        if random.random() < 0.35:
            self.pulse = 1
            self.total += random.randint(1, 3)
        else:
            self.pulse = 0
        # 10% 概率门窗翻转
        if random.random() < 0.10:
            self.magnet = 1 - self.magnet
        self.sos = 0

    def payload(self):
        return json.dumps({
            "temp": self.temp,
            "humi": self.humi,
            "magnet": self.magnet,
            "pulse": self.pulse,
            "total": self.total,
            "sos": self.sos,
        }, ensure_ascii=False).encode("utf-8")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--interval", type=float, default=0, help="主动广播间隔(秒)，0 表示只被动回复")
    parser.add_argument("--sos", action="store_true", help="发送一次 SOS 后退出")
    args = parser.parse_args()

    sim = Simulator()
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    sock.bind(("0.0.0.0", PORT))
    sock.settimeout(1.0)
    print(f"[模拟器] 已监听 UDP {PORT}，等待 APP 探测包... (Ctrl+C 退出)")

    last_broadcast = 0.0
    while True:
        try:
            data, addr = sock.recvfrom(4096)
            if data.strip() == PROBE:
                print(f"[模拟器] 收到探测包，来自 {addr[0]}，回发数据 {sim.payload().decode()}")
                sock.sendto(sim.payload(), addr)
            else:
                # 被动模式下，收到非探测包（可能是 APP 自己回环），忽略
                pass
        except socket.timeout:
            pass
        except KeyboardInterrupt:
            break

        if args.sos:
            sim.sos = 1
            print("[模拟器] 发送 SOS 告警")
            sock.sendto(sim.payload(), ("255.255.255.255", PORT))
            time.sleep(1)
            break

        if args.interval > 0:
            now = time.time()
            if now - last_broadcast >= args.interval:
                sim.step()
                sock.sendto(sim.payload(), ("255.255.255.255", PORT))
                print(f"[模拟器] 广播 {sim.payload().decode()}")
                last_broadcast = now
        else:
            # 被动模式也缓慢演化状态
            sim.step()
            time.sleep(0.5)

    sock.close()
    print("[模拟器] 已退出")


if __name__ == "__main__":
    main()
