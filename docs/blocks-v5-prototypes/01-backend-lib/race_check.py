#!/usr/bin/env python3
"""探针：很多请求同时往一个集合里加东西，会不会丢、会不会撞号？（GAP-F1-12）
用法：python3 race_check.py 标签 端口 "起服务的命令" [同时几个=30]
同时发 N 个 POST /todos，然后看：集合里是不是正好 N 条、编号是不是 1…N 各一个。"""
import json
import os
import sys
import threading

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tool"))
import httpcheck

label, port, command = sys.argv[1], int(sys.argv[2]), sys.argv[3]
n = int(sys.argv[4]) if len(sys.argv) > 4 else 30
server = httpcheck.Server(label, port, command, os.getcwd())
try:
    gate = threading.Barrier(n)
    ids, lock = [], threading.Lock()

    def one():
        try:
            gate.wait(timeout=20)
            r = httpcheck.send_raw(port, "POST", "/todos", b'{"title":"x"}')
            got = json.loads(r["body"]).get("id") if r["status"] == 201 else "状态码 %d" % r["status"]
        except Exception as e:  # 连不上之类
            got = "没发成：%s" % type(e).__name__
        with lock:
            ids.append(got)

    threads = [threading.Thread(target=one, daemon=True) for _ in range(n)]
    [t.start() for t in threads]
    [t.join(60) for t in threads]
    count = json.loads(httpcheck.send_raw(port, "GET", "/todos/count")["body"])["count"]
    ok = count == n and sorted(ids, key=str) == sorted(range(1, n + 1), key=str)
    print("[%s] 同时发 %d 个“加一条”：集合里有 %d 条，发回来的编号有 %d 种 → %s" % (label, n, count, len(set(ids)), "没丢没撞" if ok else "丢了或撞号了"))
finally:
    server.stop()
