"""宿主原生接口（L0）的 Python 实现：只用标准库。接口清单和签名见 natives.json，语义细则见 tool/README.md。"""
import os
import re
import sys
import threading
import time
import traceback
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import lc_lang as lc
import lc_runtime as _rt

BODY_LIMIT = 1048576  # 请求内容最多 1MB
_JSON = "application/json; charset=utf-8"

# —— http.serve ——

_pending = None


def http_serve(port, handler):
    global _pending
    if _pending is not None:
        raise lc.LcError("http.serve 只能登记一次")
    _pending = (int(lc.to_num(port)), handler)
    return None


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # 不打印每次访问的日志
        pass

    def _write_raw(self, status, headers, payload):
        no_body = status in (204, 304) or status < 200
        self.send_response(status)
        for k in sorted(k for k in headers if k.lower() != "content-length"):
            self.send_header(k, lc.to_text(headers[k]))
        if not no_body:
            self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if not no_body and self.command != "HEAD":
            self.wfile.write(payload)

    def _host_error(self, status, message):
        self._write_raw(status, {"Content-Type": _JSON}, lc.to_json(lc.dict_of("error", message)).encode("utf-8"))

    def _handle(self):
        length_text = self.headers.get("Content-Length") or "0"
        length = int(length_text) if re.fullmatch("[0-9]{1,12}", length_text) else 0
        if length > BODY_LIMIT:
            self.close_connection = True
            return self._host_error(413, "请求内容太大")
        raw = self.rfile.read(length) if length > 0 else b""
        try:
            body = raw.decode("utf-8")  # 不是合法 UTF-8 → 空；开头的 BOM 留着
        except UnicodeDecodeError:
            body = None
        # 请求头：名字转小写；同名的按来的顺序用 ", " 连起来；值两头的空格和制表去掉
        headers = {}
        for name, value in self.headers.items():
            name = name.lower()
            value = value.strip(" \t")
            headers[name] = headers[name] + ", " + value if name in headers else value
        path, _, query = self.path.partition("?")
        request = lc.dict_of("method", self.command, "path", path, "query", query, "headers", headers, "body", body)
        try:
            out = lc.call(self.server.lc_handler, request)
        except Exception:
            traceback.print_exc()
            return self._host_error(500, "服务器内部出错")
        if _rt._kind(out) != "obj" or not isinstance(out, dict):
            sys.stderr.write("处理函数没有返回响应\n")
            return self._host_error(500, "服务器内部出错")
        status = int(lc.to_num(lc.dict_get(out, "status")))
        if not 100 <= status <= 599:
            sys.stderr.write("响应的状态码不对\n")
            return self._host_error(500, "服务器内部出错")
        headers = lc.dict_get(out, "headers")
        self._write_raw(status, headers if isinstance(headers, dict) else {}, lc.to_text(lc.dict_get(out, "body")).encode("utf-8"))

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = do_HEAD = _handle


def ready():
    """所有模块的“启动时”做完以后由生成的代码调一次：登记过 http.serve 就开门（一直开着，直到进程被关）。"""
    if _pending is None:
        return
    env = os.environ.get("PORT", "")
    port = int(env) if re.fullmatch("[0-9]{1,5}", env) and int(env) <= 65535 else _pending[0]
    host = os.environ.get("HOST") or "0.0.0.0"
    ThreadingHTTPServer.daemon_threads = True
    server = ThreadingHTTPServer((host, port), _Handler)
    server.lc_handler = _pending[1]
    sys.stdout.write("后端已启动：http://%s:%d\n" % (host, server.server_address[1]))
    sys.stdout.flush()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


# —— store ——

_store = {}
_store_lock = threading.RLock()  # 每个请求一条线


def store_get(name):
    with _store_lock:
        return lc.copy(_store.get(lc.to_text(name)))


def store_set(name, value):
    with _store_lock:
        _store[lc.to_text(name)] = lc.copy(value)
    return None


def store_update(name, fn):
    """第 2 轮加的：函数(旧值) → [新值, 结果]；整件事拿着锁做，别的请求插不进来。"""
    key = lc.to_text(name)
    with _store_lock:
        out = lc.call(fn, _store.get(key))
        if not isinstance(out, list) or len(out) != 2:
            raise lc.LcError("store.update 的函数要返回 [新值, 结果]")
        _store[key] = out[0]
        return lc.copy(out[1])


# —— url ——

_BAD_PERCENT = re.compile(r"%(?![0-9A-Fa-f]{2})")


def url_decode(s):
    text = lc.to_text(s)
    if "%" not in text or _BAD_PERCENT.search(text):
        return text
    try:
        return urllib.parse.unquote_to_bytes(text).decode("utf-8")
    except UnicodeDecodeError:
        return text


def url_encode(s):
    return urllib.parse.quote(lc.to_text(s).encode("utf-8"), safe="")


# —— net / time / log ——


def net_fetch(method, url, data):
    return lc.fetch(method, url, data)  # 第 3 版小库现成的那个，规矩不变


def time_sleep(ms):
    time.sleep(max(0.0, lc.to_num(ms)) / 1000.0)
    return None


def time_ms():
    return float(int(time.time() * 1000))


def log_error(x):
    sys.stderr.write(lc.to_text(x) + "\n")
    sys.stderr.flush()
    return None
