#!/usr/bin/env python3
"""起服务、发原始 HTTP 请求、逐条核对响应的小工具（两个原型共用）。只连 127.0.0.1；起的进程按 pid 关掉。

用法（一般由各目录的 run.sh 调）：
  python3 httpcheck.py --cases 用例.json --name 名字 \
      --server node:18101:"node out/node/main.js" --server python:18102:"python3 out/python/main.py" [--logs 期望的日志.json]

用例文件：一个列表，每条 {"method", "target", "status", "expect" 或 "pattern", "body" 或 "bodyBytes", "headers", "type", "resHeaders"}。
target 里的 {self} 换成 http://127.0.0.1:端口，{port} 换成端口。"type" 是期望的 Content-Type（null＝不该有）。
核对：① 每个服务的每条响应＝写死的期望（状态码、Content-Type、内容逐字节）；② 各服务之间逐条比
   状态码 ＋ 全部响应头（宿主自己加的 Date / Server / Connection / Keep-Alive 除外）＋ 内容，都要逐字节相同。
"""
import json
import os
import re
import shlex
import socket
import subprocess
import sys
import threading
import time

HOST_OWNED = {"date", "server", "connection", "keep-alive"}


def send_raw(port, method, target, body=None, headers=None):
    s = socket.create_connection(("127.0.0.1", port), timeout=10)
    try:
        head = "%s %s HTTP/1.1\r\nHost: 127.0.0.1:%d\r\nConnection: close\r\n" % (method, target or "/", port)
        for k, v in (headers or {}).items():
            head += "%s: %s\r\n" % (k, v)
        if body is not None:
            head += "Content-Length: %d\r\n" % len(body)
        head += "\r\n"
        s.sendall(head.encode("utf-8") + (body or b""))
        s.settimeout(30)
        data = b""
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            data += chunk
    finally:
        s.close()
    split = data.find(b"\r\n\r\n")
    if split < 0:
        raise RuntimeError("响应不完整：%r" % data[:200])
    lines = data[:split].decode("latin-1").split("\r\n")
    status = int(lines[0].split(" ")[1])
    hs = []
    for line in lines[1:]:
        name, _, value = line.partition(":")
        hs.append((name.strip(), value.strip()))
    rest = data[split + 4:]
    low = {k.lower(): v for k, v in hs}
    if "transfer-encoding" in low:
        raise RuntimeError("响应不该分块传输")
    if "content-length" in low and int(low["content-length"]) != len(rest) and method != "HEAD":
        raise RuntimeError("Content-Length 是 %s，实际收到 %d 字节" % (low["content-length"], len(rest)))
    return {"status": status, "headers": hs, "type": low.get("content-type"), "body": rest}


class Server:
    def __init__(self, label, port, command, cwd):
        self.label, self.port = label, port
        env = dict(os.environ, PORT=str(port), HOST="127.0.0.1", PYTHONDONTWRITEBYTECODE="1")
        self.proc = subprocess.Popen(shlex.split(command), cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.lines, self.err = [], []
        self.ready = threading.Event()

        def out():
            for raw in self.proc.stdout:
                line = raw.decode("utf-8", "replace").rstrip("\n")
                if not self.ready.is_set() and re.fullmatch(r"后端已启动：http://127\.0\.0\.1:%d" % port, line):
                    self.ready.set()
                else:
                    self.lines.append(line)

        def err():
            for raw in self.proc.stderr:
                self.err.append(raw.decode("utf-8", "replace").rstrip("\n"))

        threading.Thread(target=out, daemon=True).start()
        threading.Thread(target=err, daemon=True).start()
        deadline = time.time() + 30
        while not self.ready.is_set():
            if self.proc.poll() is not None or time.time() > deadline:
                self.stop()
                raise RuntimeError("[%s] 服务没起来：\n%s\n%s" % (label, "\n".join(self.lines), "\n".join(self.err)))
            time.sleep(0.05)

    def stop(self):
        if self.proc.poll() is None:
            self.proc.kill()  # 只关自己起的这一个（按 pid）
        try:
            self.proc.wait(timeout=10)
        except subprocess.TimeoutExpired:
            pass


def run_cases(server, cases):
    out, bad = [], []
    for i, c in enumerate(cases):
        target = c["target"].replace("{self}", "http://127.0.0.1:%d" % server.port).replace("{port}", str(server.port))
        body = bytes(c["bodyBytes"]) if c.get("bodyBytes") is not None else (c["body"].encode("utf-8") if c.get("body") is not None else None)
        try:
            r = send_raw(server.port, c["method"], target, body, c.get("headers"))
        except Exception as e:  # 连不上、响应不完整
            r = {"status": -1, "headers": [], "type": None, "body": str(e).encode("utf-8")}
        out.append(r)
        why = []
        if r["status"] != c["status"]:
            why.append("状态码 %s，期望 %s" % (r["status"], c["status"]))
        if "type" in c and r["type"] != c["type"]:
            why.append("Content-Type %r，期望 %r" % (r["type"], c["type"]))
        if c.get("pattern") is not None:
            if not re.search(c["pattern"], r["body"].decode("utf-8", "replace")):
                why.append("内容 %r 不符合 %s" % (r["body"][:80], c["pattern"]))
        elif r["body"] != c["expect"].encode("utf-8"):
            why.append("内容 %s，期望 %s" % (r["body"].decode("utf-8", "replace")[:300], c["expect"][:300]))
        for k, v in (c.get("resHeaders") or {}).items():
            got = dict((a.lower(), b) for a, b in r["headers"]).get(k.lower())
            if got != v:
                why.append("响应头 %s 是 %r，期望 %r" % (k, got, v))
        if why:
            bad.append("  [%s] 第 %d 条 %s %s：%s" % (server.label, i + 1, c["method"], c["target"], "；".join(why)))
    return out, bad


def comparable(r):
    return (r["status"], [(k, v) for k, v in r["headers"] if k.lower() not in HOST_OWNED], r["body"])


def main(argv):
    cases_file, name, servers, logs_file, cwd = None, "", [], None, os.getcwd()
    i = 0
    while i < len(argv):
        if argv[i] == "--cases":
            cases_file = argv[i + 1]
        elif argv[i] == "--name":
            name = argv[i + 1]
        elif argv[i] == "--server":
            servers.append(argv[i + 1].split(":", 2))
        elif argv[i] == "--logs":
            logs_file = argv[i + 1]
        i += 2
    cases = json.load(open(cases_file, encoding="utf-8"))
    results, failed = {}, False
    for label, port, command in servers:
        server = Server(label, int(port), command, cwd)
        try:
            results[label], bad = run_cases(server, cases)
            time.sleep(0.3)
            print("[%s] %s：%d 条请求，%d 条等于写死的期望，%d 条不等" % (name, label, len(cases), len(cases) - len(bad), len(bad)))
            for line in bad:
                print(line)
            failed = failed or bool(bad)
            if logs_file:
                want = json.load(open(logs_file, encoding="utf-8"))
                same = server.lines == want
                print("[%s] %s：标准输出 %d 行，%s期望的 %d 行" % (name, label, len(server.lines), "等于" if same else "不等于", len(want)))
                if not same:
                    failed = True
                    print("  实际：%s" % json.dumps(server.lines, ensure_ascii=False)[:1000])
            if server.err:
                print("[%s] %s：错误输出 %d 行（前 5 行）：" % (name, label, len(server.err)))
                for line in server.err[:5]:
                    print("    " + line[:200])
        finally:
            server.stop()
    labels = list(results)
    for other in labels[1:]:
        diff = [i for i in range(len(cases)) if cases[i].get("pattern") is None and comparable(results[labels[0]][i]) != comparable(results[other][i])]
        print("[%s] %s 和 %s 逐条比（状态码＋响应头＋内容，逐字节）：%d 条相同，%d 条不同" % (name, labels[0], other, len(cases) - len(diff) - sum(1 for c in cases if c.get("pattern") is not None), len(diff)))
        for i in diff[:10]:
            failed = True
            print("  第 %d 条 %s %s\n    %s：%r\n    %s：%r" % (i + 1, cases[i]["method"], cases[i]["target"], labels[0], comparable(results[labels[0]][i]), other, comparable(results[other][i])))
    print("[%s] 结果：%s" % (name, "有不一致" if failed else "全部通过"))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
