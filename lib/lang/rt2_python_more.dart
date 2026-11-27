/// 规矩版本 2 的小库·Python·第三段（接在 rt2_python_dyn.dart 后面，同一个 `lc2.py`）：随机字节、文件、请求别的网址。
/// 细则见 docs/blocks-v5-parts/C-library-system.md 9.1、9.2 和 B-gen-notes.md 第 14 节。只用 Python 自带的库。
library;

const String kRt2PythonMore = r'''

# —— 随机字节、文件、请求别的网址 ——
def hostRandomBytes(n):
    if n < 1 or n > 1024:
        fail("随机字节的个数要在 1 到 1024 之间")
    return list(_os.urandom(n))


def _file_path(p):
    if p == "" or p[0] in "/\\" or _re.match(r"[A-Za-z]:", p) or ".." in _re.split(r"[/\\]", p):
        fail("路径不对：只能用工程文件夹里面的相对路径")
    return _os.path.join(_os.getcwd(), p)


def fileRead(p):
    full = _file_path(p)
    try:
        with open(full, "rb") as f:
            raw = f.read()
    except FileNotFoundError:
        fail("读不了文件：没有「" + p + "」")
    except OSError:
        fail("读不了文件：「" + p + "」")
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        fail("读不了文件：「" + p + "」不是 UTF-8 文字")


def fileWrite(p, text):
    full = _file_path(p)
    tmp = full + ".lctmp" + str(_os.getpid())
    try:
        _os.makedirs(_os.path.dirname(full), exist_ok=True)
        with open(tmp, "wb") as f:
            f.write(text.encode("utf-8"))
        _os.replace(tmp, full)
    except (OSError, UnicodeEncodeError):
        try:
            _os.unlink(tmp)
        except OSError:
            pass  # 临时文件本来就没写出来
        fail("写不了文件：「" + p + "」")


def fileExists(p):
    return _os.path.exists(_file_path(p))


def fileList(p):
    full = _file_path(p)
    try:
        return sorted(_os.listdir(full))
    except OSError:
        fail("列不了文件夹：「" + p + "」")


def fileRemove(p):
    full = _file_path(p)
    try:
        if not _os.path.isfile(full):
            raise OSError()
        _os.unlink(full)
    except OSError:
        fail("删不了文件：「" + p + "」")


_URL_KEEP = frozenset(b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~:/?[]@!$&'()*+,;=")
_HEX = frozenset(b"0123456789ABCDEFabcdef")
_FETCH_METHODS = ("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS")
_FETCH_SKIP = ("host", "content-length", "connection", "expect", "upgrade")


# 网址里的空格、中文、写法不对的百分号先按 UTF-8 做百分号转义（各语言自己的处理不一样，这里统一）；# 后面的不发。
def _encode_url(s):
    raw = s.split("#", 1)[0].encode("utf-8")
    out = []
    for i, c in enumerate(raw):
        escaped = c == 0x25 and i + 2 < _b.len(raw) and raw[i + 1] in _HEX and raw[i + 2] in _HEX
        out.append(chr(c) if escaped or c in _URL_KEEP else "%%%02X" % c)
    return "".join(out)


def hostFetch(method, url, headers, body, timeout_ms):
    import socket
    import urllib.error
    import urllib.request

    _line_check()  # 被取消了的事，到了要等的地方就停
    if not _re.match(r"https?://", url, _re.IGNORECASE):
        fail("请求不了：网址要以 http:// 或 https:// 开头")
    if method not in _FETCH_METHODS:
        fail("请求不了：不认识的方式「" + method + "」")
    if timeout_ms <= 0:
        fail("请求不了：超时毫秒要大于 0")
    hs = {k: headers[k] for k in keys(headers) if k.lower() not in _FETCH_SKIP}
    low = {k.lower() for k in hs}
    if "user-agent" not in low:
        hs["User-Agent"] = "LopiCode"
    payload = None
    if body is not None and method not in ("GET", "HEAD"):
        payload = body.encode("utf-8")
        if "content-type" not in low:
            hs["Content-Type"] = "text/plain; charset=utf-8"
    try:
        request = urllib.request.Request(_encode_url(url), data=payload, headers=hs, method=method)
        try:
            res = urllib.request.urlopen(request, timeout=timeout_ms / 1000)
        except urllib.error.HTTPError as e:
            res = e  # 404、500 这些不算出错：照样把回应交回去
        with res:
            raw = res.read()
            back = {}
            for k, v in res.headers.items():
                k = k.lower()
                back[k] = back[k] + ", " + v if k in back else v
            return {"status": float(res.status), "headers": back, "body": raw.decode("utf-8", errors="replace")}
    except LcError:
        raise
    except Exception as e:  # 连不上、超时、网址写错……
        reason = getattr(e, "reason", e)
        timed_out = isinstance(e, (TimeoutError, socket.timeout)) or isinstance(reason, (TimeoutError, socket.timeout))
        fail("请求超时了" if timed_out else "请求不了：连不上")
''';
