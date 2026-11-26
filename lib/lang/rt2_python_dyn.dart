/// 规矩版本 2 的小库·Python·下半（列表、字典、“任意”、输出）。上半在 rt2_python.dart。
library;

import 'package:lopicode/lang/rt2_python.dart';

/// 整份小库。
const String kRt2PythonSource = kRt2PythonHead + _tail;

const String _tail = r'''
# —— 列表、字典 ——
def _out_of(i, n):
    fail("位置 " + str(i) + " 超出了列表的范围（共 " + str(n) + " 项）")


def at(xs, i):
    return xs[i] if 0 <= i < _b.len(xs) else _out_of(i, _b.len(xs))


def setAt(xs, i, v):
    if 0 <= i < _b.len(xs):
        xs[i] = v
    else:
        _out_of(i, _b.len(xs))


def push(xs, v):
    xs.append(v)


def pop(xs):
    return xs.pop() if xs else None


def len(x):
    return _b.len(x)


def items(xs):
    return list(xs)


def keys(d):
    return sorted(d.keys())


def get(d, k):
    return d.get(k)


def dictSet(d, k, v):
    d[k] = v


def dictRemove(d, k):
    d.pop(k, None)


dictKeys = keys


def dictValues(d):
    return [d[k] for k in keys(d)]


def dictHas(d, k):
    return k in d


def must(x):
    return fail("这里的值是空，不能直接用") if x is None else x


def listMap(xs, f):
    return [f(v) for v in list(xs)]


def listFilter(xs, f):
    return [v for v in list(xs) if f(v)]


def listReduce(xs, f, init):
    acc = init
    for v in list(xs):
        acc = f(acc, v)
    return acc


def listFind(xs, f):
    for v in list(xs):
        if f(v):
            return v
    return None


def listEvery(xs, f):
    return all(f(v) for v in list(xs))


def listSome(xs, f):
    return any(f(v) for v in list(xs))


def listEach(xs, f):
    for v in list(xs):
        f(v)


def listJoin(xs, sep):
    return sep.join(xs)


def listReverse(xs):
    return xs[::-1]


def listConcat(a, b):
    return a + b


def listSlice(xs, a, b):
    a = _clamp(a, _b.len(xs))
    b = _clamp(b, _b.len(xs))
    return [] if a >= b else xs[a:b]


def listIndexOf(xs, v):
    for i, x in enumerate(xs):
        if eq(x, v):
            return i
    return -1


def listContains(xs, v):
    return listIndexOf(xs, v) >= 0


def range(a, b, s):
    return [a + k * s for k in _b.range(_b.min(steps(a, b, s), 10000))]


def recCopy(r, changes):
    o = _copy.copy(r)
    for k, v in changes.items():
        setattr(o, k, v)
    return o


# —— “任意”的值之间（严格：不偷偷转换） ——
def _dnum(op, x):
    return float(x) if _isnum(x) else fail(op + "的两边要数字，拿到的是" + kind(x))


def dadd(a, b):
    return _dnum("加法", a) + _dnum("加法", b)


def dsub(a, b):
    return _dnum("减法", a) - _dnum("减法", b)


def dmul(a, b):
    return _dnum("乘法", a) * _dnum("乘法", b)


def ddiv(a, b):
    return fdiv(_dnum("除法", a), _dnum("除法", b))


def dpow(a, b):
    return fpow(_dnum("乘方", a), _dnum("乘方", b))


def didiv(a, b):
    return float(idiv(asInt(a), asInt(b)))


def dmod(a, b):
    return float(imod(asInt(a), asInt(b)))


def dynGet(x, k):
    if isinstance(x, list):
        return at(x, asInt(k))
    if isinstance(x, dict):
        return get(x, asText(k))
    fail("这里要列表或字典，拿到的是" + kind(x))


def dynSet(x, k, v):
    if isinstance(x, list):
        return setAt(x, asInt(k), v)
    if isinstance(x, dict):
        return dictSet(x, asText(k), v)
    fail("这里要列表或字典，拿到的是" + kind(x))


def dynPush(x, v):
    push(asList(x), v)


def dynPop(x):
    return pop(asList(x))


def dynRemove(x, k):
    dictRemove(asDict(x), asText(k))


def dynOrElse(x, d):
    return d if x is None else x


def dynSize(x):
    if isinstance(x, (str, list, dict)):
        return _b.len(x)
    fail("这里要文字、列表或字典，拿到的是" + kind(x))


def _jstr(s):
    return _json.dumps(s, ensure_ascii=False)


def toJson(x):
    if x is None:
        return "null"
    if isinstance(x, bool):
        return boolText(x)
    if isinstance(x, (int, float)):
        return fmtNum(x) if math.isfinite(x) else "null"
    if isinstance(x, str):
        return _jstr(x)
    if isinstance(x, list):
        return "[" + ",".join(toJson(v) for v in x) + "]"
    if isinstance(x, dict):
        return "{" + ",".join(_jstr(k) + ":" + toJson(x[k]) for k in keys(x)) + "}"
    if isinstance(x, Enum):
        return _jstr(x.name)
    if isinstance(x, Rec):
        fs = vars(x)
        return "{" + ",".join(_jstr(k[2:] if k.startswith("m_") else k) + ":" + toJson(fs[k]) for k in sorted(fs)) + "}"
    return "null"


def _bad_const(_):
    raise ValueError("不是 JSON")


def fromJson(s):
    try:
        return _json.loads(s, parse_int=float, parse_constant=_bad_const)
    except (ValueError, RecursionError):
        fail("这段文字不是 JSON")


def dtext(x):
    if x is None:
        return ""
    if isinstance(x, bool):
        return boolText(x)
    if isinstance(x, (int, float)):
        return fmtNum(x)
    if isinstance(x, str):
        return x
    if isinstance(x, Enum):
        return x.name
    if isinstance(x, (list, dict, Rec)):
        return toJson(x)
    if isinstance(x, Obj):
        return "[" + getattr(type(x), "lcName", "对象") + "]"
    return "[函数]" if callable(x) else "[对象]"


def orElse(x, f):
    return f() if x is None else x


# —— 输出：写一行就马上写出去（服务被关掉的时候不会丢）；几条线同时写，一行也不会被拆开 ——
_out_lock = _threading.Lock()
_wrote = False


def log(s):
    global _wrote
    with _out_lock:
        _wrote = True
        sys.stdout.buffer.write((s + "\n").encode("utf-8"))
        sys.stdout.buffer.flush()


# —— 是不是数字、网址解码 ——
_NUM = _re.compile(r"[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?")
_BAD_PCT = _re.compile(r"%(?![0-9A-Fa-f]{2})")


def isNumeric(x):
    if isinstance(x, bool):
        return False
    if isinstance(x, (int, float)):
        return True
    if not isinstance(x, str):
        return False
    s = x.strip(" \t\n\r")
    return _NUM.fullmatch(s) is not None and math.isfinite(float(s))


def toNumber(s):
    if not isNumeric(s):
        fail("「" + s + "」变不成数字")
    return float(s.strip(" \t\n\r"))


# 这个值是不是某一类：null bool number text list dict function object。
def isType(x, name):
    if name == "null":
        return x is None
    if name == "bool":
        return isinstance(x, bool)
    if name == "number":
        return isinstance(x, (int, float)) and not isinstance(x, bool)
    if name == "text":
        return isinstance(x, str)
    if name == "list":
        return isinstance(x, list)
    if name == "dict":
        return isinstance(x, dict)
    if name == "function":
        return callable(x) and not isinstance(x, type)
    if name == "object":
        return isinstance(x, (Obj, Rec, Enum))
    fail("没有「" + name + "」这一类值")


# 两个字典合成一个新的：后面的盖住前面的。
def dictMerge(a, b):
    out = dict(a)
    out.update(b)
    return out


def urlDecode(s):
    if _BAD_PCT.search(s):
        fail("这段网址编码解不开")
    try:
        return _urlparse.unquote(s, encoding="utf-8", errors="strict")
    except UnicodeDecodeError:
        fail("这段网址编码解不开")


# —— 宿主（清单见 host_v2.dart）——
def hostPrint(s, ch):
    if ch == "out":
        log(s)
    elif ch == "err":
        sys.stderr.buffer.write((s + "\n").encode("utf-8"))
        sys.stderr.buffer.flush()
    else:
        fail("通道只能是 out 或 err")


def hostNow():
    return int(_time.time() * 1000)


def _copy_val(v):
    if isinstance(v, list):
        return [_copy_val(x) for x in v]
    if isinstance(v, dict):
        return {k: _copy_val(x) for k, x in v.items()}
    return v


# 格子：每个名字一把锁。别的线同时改同一个名字＝排队；改它的函数里再改它＝报错（不然会自己等自己）。
_store = {}
_store_lock = _threading.Lock()
_store_locks = {}


def storeRead(name):
    with _store_lock:
        return _copy_val(_store.get(name))


def storeUpdate(name, f):
    with _store_lock:
        lk = _store_locks.setdefault(name, [_threading.Lock(), None])
    me = _threading.get_ident()
    if lk[1] == me:
        fail("「" + name + "」这个格子正在改，不能在改它的函数里再改它")
    with lk[0]:
        lk[1] = me
        try:
            v = _copy_val(f(storeRead(name)))
            with _store_lock:
                _store[name] = v
            return _copy_val(v)
        finally:
            lk[1] = None


def hostEnv(name):
    return _os.environ.get(name)


# —— 要等的事：一件事一条线 ——
def hostSleep(ms):
    _time.sleep(max(0, ms) / 1000.0)


class Task:
    def __init__(self, f):
        self._done = _threading.Event()
        self._val = None
        self._err = None
        _threading.Thread(target=self._run, args=(f,), daemon=True).start()

    def _run(self, f):
        try:
            self._val = f()
        except BaseException as e:  # 出了错先记着，等它的时候再抛
            self._err = e
        finally:
            self._done.set()


def spawn(f):
    return Task(f)


def wait(t):
    t._done.wait()
    if t._err is not None:
        raise t._err
    return t._val


# —— 开服务（细则见 docs/blocks-v5-parts/C-library-system.md 9.1 和 B-gen-notes.md 第 12 节）——
_BODY_LIMIT = 1048576


def _err_text(e):
    return "出错：" + str(e) if isinstance(e, LcError) else "".join(_traceback.format_exception(e)).rstrip("\n")


def hostServe(port, host, handler):
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, format, *args):  # 不打印每次访问的日志
            pass

        def _write(self, status, headers, text):
            payload = text.encode("utf-8", "replace")
            no_body = status in (204, 304) or status < 200
            self.send_response(status)
            for k in sorted(k for k in headers if k.lower() != "content-length"):
                self.send_header(k, dtext(headers[k]))
            if not no_body:
                self.send_header("Content-Length", str(_b.len(payload)))
            self.end_headers()
            if not no_body and self.command != "HEAD":
                self.wfile.write(payload)

        def _host_error(self, status, message):
            self._write(status, {"Content-Type": "application/json; charset=utf-8"}, toJson({"error": message}))

        def _handle(self):
            length_text = self.headers.get("Content-Length") or "0"
            length = int(length_text) if _re.fullmatch("[0-9]{1,12}", length_text) else 0
            if length > _BODY_LIMIT:
                self.close_connection = True
                return self._host_error(413, "请求内容太大")
            raw = self.rfile.read(length) if length > 0 else b""
            try:
                body = raw.decode("utf-8")
            except UnicodeDecodeError:
                body = None
            headers = {}
            for name, value in self.headers.items():
                name = name.lower()
                value = value.strip(" \t")
                headers[name] = headers[name] + ", " + value if name in headers else value
            path, _, query = self.path.partition("?")
            request = {"method": self.command, "path": path, "query": query, "headers": headers, "body": body}
            try:
                out = handler(request)
            except Exception as e:  # 处理函数自己没接住的错：记到错误输出，回 500
                sys.stderr.write(_err_text(e) + "\n")
                sys.stderr.flush()
                return self._host_error(500, "服务器内部出错")
            status = out.get("status") if isinstance(out, dict) else None
            if isinstance(status, float) and status.is_integer():
                status = int(status)
            if not isinstance(status, int) or isinstance(status, bool) or not 100 <= status <= 599:
                sys.stderr.write("处理函数返回的响应不对（要一个字典，status 是 100 到 599 的整数）\n")
                sys.stderr.flush()
                return self._host_error(500, "服务器内部出错")
            hs = out.get("headers")
            self._write(status, hs if isinstance(hs, dict) else {}, dtext(out.get("body")))

        do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_OPTIONS = do_HEAD = _handle

    if port < 0 or port > 65535:
        fail("开不了服务：端口要在 0 到 65535 之间")
    ThreadingHTTPServer.daemon_threads = True
    try:
        server = ThreadingHTTPServer((host, port), Handler)
    except OSError:
        fail("开不了服务：" + host + ":" + str(port) + " 用不了")
    log("后端已启动：http://" + host + ":" + str(server.server_address[1]))
    try:
        server.serve_forever()
    finally:
        server.server_close()


def run(main):
    failed = False
    try:
        main()
    except LcError as e:
        log("出错：" + str(e))
        failed = True
    except KeyboardInterrupt:  # 被 Ctrl+C 停掉：安静地收场
        pass
    if not _wrote:  # 什么都没写过的，补一个空行（和原来“攒到最后一次写”的样子一样）
        sys.stdout.buffer.write(b"\n")
    sys.stdout.buffer.flush()
    if failed:
        sys.exit(1)
''';
