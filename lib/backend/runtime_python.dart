/// Python 运行时小库的源码（生成的工程里的 `lc_runtime.py`）。每份工程都一样。
///
/// 只用标准库（`http.server` 的 ThreadingHTTPServer）。值的规矩见 backend_ir.dart 的 `kBeRuntimeFns`，
/// 改这里的行为要同时改别的语言的小库（`test/backend_conformance_test.dart` 会比对各语言的响应是否逐字节相同）。
library;

const String kPythonRuntimeSource = r'''
"""LopiCode 后端运行时小库（Python，只用标准库，不用装任何包）。

每份生成的工程都一样，不用改；你的接口在 server.py 里。
"""
import json
import math
import os
import re
import sys
import threading
import time
import traceback
import urllib.parse
import urllib.request
from decimal import ROUND_HALF_UP, Context, Decimal
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BODY_LIMIT = 1048576  # 请求内容最多 1MB
REPEAT_LIMIT = 10000  # “重复”最多做这么多遍
FETCH_TIMEOUT_SECONDS = 10  # “请求别的网址”最多等 10 秒
JSON_DEPTH_LIMIT = 64  # 请求内容的 JSON 最多套这么多层

# —— 值：空 / 是否 / 数字 / 文字 / 列表 / 对象 ——

_NUM = re.compile(r"[ \t\r\n]*[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?[ \t\r\n]*")
_ROUND12 = Context(prec=12, rounding=ROUND_HALF_UP)
_SURROGATES = re.compile("[\ud800-\udfff]")


def _kind(v):
    if v is None:
        return "null"
    if isinstance(v, bool):  # 要先判断：Python 里 bool 也算 int
        return "bool"
    if isinstance(v, (int, float)):
        return "num"
    if isinstance(v, str):
        return "text"
    if callable(v):  # “函数”这种值（积木第 4 版；怎么造、怎么调在 lc_lang.py 里）
        return "fn"
    return "list" if isinstance(v, list) else "obj"


def _fin(n):
    return n if math.isfinite(n) else 0.0


def to_num(v):
    """转成数字：转不了的当 0。"""
    kind = _kind(v)
    if kind == "num":
        return _fin(float(v))
    if kind == "text":
        return _fin(float(v)) if _NUM.fullmatch(v) else 0.0
    return 1.0 if v is True else 0.0


def fmt_num(v):
    """数字的写法：整数不带小数点；其余保留 12 位有效数字（0.1 + 0.2 写成 0.3）。"""
    v = float(v)
    if not math.isfinite(v) or v == 0:
        return "0"
    if v == math.floor(v) and abs(v) < 1e15:
        return str(int(v))
    sign, digit_tuple, exponent = _ROUND12.create_decimal(Decimal(v)).as_tuple()
    e = len(digit_tuple) - 1 + exponent
    digits = "".join(str(d) for d in digit_tuple).rstrip("0")
    minus = "-" if sign else ""
    if e >= 15 or e < -7:
        return minus + digits[0] + ("." + digits[1:] if len(digits) > 1 else "") + "e" + str(e)
    if e >= len(digits) - 1:
        return minus + digits + "0" * (e - len(digits) + 1)
    if e >= 0:
        return minus + digits[: e + 1] + "." + digits[e + 1 :]
    return minus + "0." + "0" * (-e - 1) + digits


def to_json(v):
    """写成 JSON：对象的键排好序，数字按上面的写法。"""
    kind = _kind(v)
    if kind == "null":
        return "null"
    if kind == "bool":
        return "true" if v else "false"
    if kind == "num":
        return fmt_num(v)
    if kind == "text":
        return json.dumps(v, ensure_ascii=False)
    if kind == "list":
        return "[" + ",".join(to_json(x) for x in v) + "]"
    if kind == "fn":  # 函数写不成 JSON：当空
        return "null"
    return "{" + ",".join(json.dumps(k, ensure_ascii=False) + ":" + to_json(v[k]) for k in sorted(v)) + "}"


def to_text(v):
    """转成文字。"""
    kind = _kind(v)
    if kind == "null":
        return ""
    if kind == "text":
        return v
    if kind == "fn":
        name = getattr(v, "lc_name", "")
        return "[函数 " + name + "]" if name else "[函数]"
    return to_json(v)


def truthy(v):
    """算不算“是”：空、否、0、空文字算“否”。"""
    kind = _kind(v)
    if kind == "null":
        return False
    if kind == "bool":
        return v
    if kind == "num":
        return v != 0
    if kind == "text":
        return v != ""
    return True


def eq(a, b):
    """“等于”：类型一样直接比；不一样就都转成文字再比。"""
    kind = _kind(a)
    if kind != _kind(b):
        return to_text(a) == to_text(b)
    if kind in ("list", "obj"):
        return to_json(a) == to_json(b)
    if kind == "num":
        return float(a) == float(b)
    if kind == "fn":  # 两个函数：是同一个，或者是同一个有名字的函数
        name = getattr(a, "lc_name", "")
        return a is b or (name != "" and name == getattr(b, "lc_name", ""))
    return a == b


def _well_formed(s):
    return _SURROGATES.sub("\ufffd", s)


def _norm(v, depth=0):
    """把 json.loads 出来的值收拾干净：不成对的代理项换成 U+FFFD，超出范围的数字当 0；套得太深就报错（整份当成空）。"""
    kind = _kind(v)
    if kind == "text":
        return _well_formed(v)
    if kind == "num":
        return _fin(float(v))
    if kind in ("list", "obj"):
        if depth >= JSON_DEPTH_LIMIT:
            raise ValueError("JSON 套得太深")
        if kind == "list":
            return [_norm(x, depth + 1) for x in v]
        return {_well_formed(k): _norm(x, depth + 1) for k, x in v.items()}
    return v


# —— 运算 ——


def add(a, b):
    return _fin(to_num(a) + to_num(b))


def sub(a, b):
    return _fin(to_num(a) - to_num(b))


def mul(a, b):
    return _fin(to_num(a) * to_num(b))


def div(a, b):
    d = to_num(b)
    return 0.0 if d == 0 else _fin(to_num(a) / d)


def mod(a, b):
    d = to_num(b)
    return 0.0 if d == 0 else _fin(math.fmod(to_num(a), d))


def ne(a, b):
    return not eq(a, b)


def lt(a, b):
    return to_num(a) < to_num(b)


def le(a, b):
    return to_num(a) <= to_num(b)


def gt(a, b):
    return to_num(a) > to_num(b)


def ge(a, b):
    return to_num(a) >= to_num(b)


def all_of(a, b):
    return truthy(a) and truthy(b)


def any_of(a, b):
    return truthy(a) or truthy(b)


def is_not(x):
    return not truthy(x)


def is_null(x):
    return x is None


def join(*items):
    return "".join(to_text(x) for x in items)


def size(x):
    return len(x) if _kind(x) in ("list", "text", "obj") else 0


def obj(*pairs):
    """obj("title", "买菜", "done", False) → {"title": "买菜", "done": False}"""
    return {pairs[i]: pairs[i + 1] for i in range(0, len(pairs) - 1, 2)}


def field(o, key):
    return o.get(key) if _kind(o) == "obj" else None


def times(x):
    return min(max(int(to_num(x)), 0), REPEAT_LIMIT)


def items(x):
    return list(x) if _kind(x) == "list" else []


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def _say(line):
    """往标准输出写一行，马上送出去。"""
    sys.stdout.write(line + "\n")
    sys.stdout.flush()


def log(x):
    _say(to_text(x))


# —— 数据集合（存在内存里，进程重启就没了）——

_collections = {}
_lock = threading.Lock()  # 每个请求一个线程，动集合要排队


def collection(name):
    c = _collections.get(name)
    if c is None:
        c = {"next": 1, "rows": []}
        _collections[name] = c
    return c


def _index(rows, id):
    want = to_num(id)
    for i, row in enumerate(rows):
        if row["id"] == want:
            return i
    return -1


def db_all(name):
    with _lock:
        return list(collection(name)["rows"])


def db_count(name):
    with _lock:
        return len(collection(name)["rows"])


def db_get(name, id):
    with _lock:
        rows = collection(name)["rows"]
        i = _index(rows, id)
        return rows[i] if i >= 0 else None


def db_find(name, key, value):
    with _lock:
        return [row for row in collection(name)["rows"] if eq(field(row, key), value)]


def db_insert(name, value):
    with _lock:
        c = collection(name)
        row = dict(value) if _kind(value) == "obj" else {}
        row["id"] = c["next"]
        c["next"] += 1
        c["rows"].append(row)
        return row


def db_update(name, id, value):
    """改的是一份新的记录（之前读出来的那份不会跟着变）。"""
    with _lock:
        rows = collection(name)["rows"]
        i = _index(rows, id)
        if i < 0:
            return None
        if _kind(value) != "obj":
            return rows[i]
        row = dict(rows[i])
        row.update(value)
        row["id"] = rows[i]["id"]
        rows[i] = row
        return row


def db_delete(name, id):
    with _lock:
        rows = collection(name)["rows"]
        i = _index(rows, id)
        if i < 0:
            return False
        del rows[i]
        return True


# —— 请求 ——

_BAD_PERCENT = re.compile(r"%(?![0-9A-Fa-f]{2})")


def _pct(s):
    """百分号解码；写法不对（%zz、解出来不是合法 UTF-8）就原样返回。"""
    if "%" not in s or _BAD_PERCENT.search(s):
        return s
    try:
        return urllib.parse.unquote_to_bytes(s).decode("utf-8")
    except UnicodeDecodeError:
        return s


def _parse_query(raw):
    out = {}
    for part in raw.split("&"):
        if part == "":
            continue
        key, eq_sign, value = part.partition("=")
        key = _pct(key.replace("+", " "))
        value = _pct(value.replace("+", " ")) if eq_sign else ""
        out.setdefault(key, value)
    return out


def _reject_constant(name):
    raise ValueError("JSON 里不许有 " + name)


def _parse_body(raw):
    if len(raw) == 0:
        return None
    try:
        return _norm(json.loads(raw.decode("utf-8"), parse_int=float, parse_constant=_reject_constant))
    except (ValueError, RecursionError):
        return None


class Request:
    def __init__(self, params, raw_query, headers, raw_body):
        self.params = params
        self.raw_query = raw_query
        self.headers = headers
        self.raw_body = raw_body
        self._query = None
        self._parsed = False
        self._body = None


def path_param(req, name):
    return req.params.get(name)


def query(req, name):
    if req._query is None:
        req._query = _parse_query(req.raw_query)
    return req._query.get(name)


def body(req):
    if not req._parsed:
        req._parsed = True
        req._body = _parse_body(req.raw_body)
    return req._body


def body_field(req, name):
    return field(body(req), name)


def header(req, name):
    values = req.headers.get_all(name)
    # http.server 会留着值末尾的空格，别的语言都去掉了
    return ", ".join(v.strip(" \t") for v in values) if values else None


# —— 响应 ——


def _status_of(v):
    n = int(to_num(v))
    return n if 200 <= n <= 599 else 200


def send_json(status, value):
    return (_status_of(status), "application/json; charset=utf-8", to_json(value).encode("utf-8"))


def send_text(status, value):
    return (_status_of(status), "text/plain; charset=utf-8", to_text(value).encode("utf-8"))


def _error(status, message):
    return send_json(status, obj("error", message))


# —— 请求别的网址 ——


_URL_KEEP = frozenset(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?#[]@!$&'()*+,;=")
_HEX = frozenset(b"0123456789ABCDEFabcdef")


def _encode_url(s):
    """网址里的空格、中文、写法不对的百分号先按 UTF-8 做百分号转义（各语言自己的处理不一样，这里统一）。"""
    raw = s.encode("utf-8")
    out = []
    for i, c in enumerate(raw):
        escaped = c == 0x25 and i + 2 < len(raw) and raw[i + 1] in _HEX and raw[i + 2] in _HEX
        out.append(chr(c) if escaped or c in _URL_KEEP else "%%%02X" % c)
    return "".join(out)


def fetch(method, url, data):
    """成功（2xx）返回响应的文字；失败、超时、不是 http(s) 网址一律返回 None。"""
    target = to_text(url)
    if not re.match(r"https?://", target, re.IGNORECASE):
        return None
    if "@" in re.split("[/?#]", target.split("://", 1)[1], maxsplit=1)[0]:
        return None  # 主机那一段带 @（用户名密码）的不请求
    try:
        target = _encode_url(target)
        payload = None
        headers = {}
        if method == "POST" and data is not None:
            payload = to_json(data).encode("utf-8")
            headers["Content-Type"] = "application/json; charset=utf-8"
        request = urllib.request.Request(target, data=payload, headers=headers, method="POST" if method == "POST" else "GET")
        with urllib.request.urlopen(request, timeout=FETCH_TIMEOUT_SECONDS) as res:
            if not 200 <= res.status <= 299:
                return None
            text = res.read().decode("utf-8", errors="replace")
            return text[1:] if text.startswith("\ufeff") else text  # 开头的 BOM 去掉一个
    except Exception:  # 连不上、超时、4xx / 5xx、网址写错……都算失败
        return None


# —— 路由与启动 ——

_routes = []


def route(method, path, handler):
    """登记一个接口。path 里的 :名字 是路径参数。"""
    _routes.append((method, [s for s in path.split("/") if s != ""], handler))


def _match(pattern, segments):
    """路径对得上就返回参数表，否则 None。"""
    if len(pattern) != len(segments):
        return None
    params = {}
    for want, got in zip(pattern, segments):
        if want.startswith(":"):
            params[want[1:]] = got
        elif want != got:
            return None
    return params


class _Handler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):  # 不打印每次访问的日志
        pass

    def _write(self, out):
        status, content_type, payload = out
        self.send_response(status)
        self.send_header("Access-Control-Allow-Origin", "*")
        if status in (204, 304):
            self.end_headers()
            return
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        if self.command != "HEAD":  # HEAD 只要响应头
            self.wfile.write(payload)

    def _handle(self):
        length_text = self.headers.get("Content-Length") or "0"
        length = int(length_text) if re.fullmatch("[0-9]{1,12}", length_text) else 0
        if length > BODY_LIMIT:
            self.close_connection = True
            return self._write(_error(413, "请求内容太大"))
        raw_body = self.rfile.read(length) if length > 0 else b""
        if self.command == "OPTIONS":
            # 浏览器跨域调用前的“预检”
            self.send_response(204)
            self.send_header("Access-Control-Allow-Origin", "*")
            self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
            self.send_header("Access-Control-Allow-Headers", "*")
            return self.end_headers()
        raw_path, _, raw_query = self.path.partition("?")
        segments = [_pct(s) for s in raw_path.split("/") if s != ""]
        path_matched = False
        for method, pattern, handler in _routes:
            params = _match(pattern, segments)
            if params is None:
                continue
            path_matched = True
            if method != self.command:
                continue
            try:
                out = handler(Request(params, raw_query, self.headers, raw_body))
            except Exception:
                traceback.print_exc()
                out = _error(500, "服务器内部出错")
            # 没有碰到“返回”积木：204 空响应
            return self._write(out if out is not None else (204, "", b""))
        return self._write(_error(405, "这个地址不支持这种请求方式") if path_matched else _error(404, "没有这个接口"))

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = do_HEAD = _handle


def start(default_port):
    """启动服务。端口先看环境变量 PORT，没有就用 default_port；HOST 默认 0.0.0.0（所有网卡）。"""
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # 终端不是 UTF-8 时也能打印中文
    except (AttributeError, ValueError):
        pass
    env = os.environ.get("PORT", "")
    port = int(env) if re.fullmatch("[0-9]{1,5}", env) and int(env) <= 65535 else default_port
    host = os.environ.get("HOST") or "0.0.0.0"
    ThreadingHTTPServer.daemon_threads = True
    server = ThreadingHTTPServer((host, port), _Handler)
    _say("后端已启动：http://%s:%d" % (host, server.server_address[1]))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
''';
