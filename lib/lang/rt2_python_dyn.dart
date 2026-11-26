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


def range(a, b):
    return list(_b.range(a, b + 1))


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


# —— 输出：攒起来，最后一次写出 ——
_out = []


def log(s):
    _out.append(s)


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
        _out.append(s)
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


_store = {}
_store_busy = set()


def storeRead(name):
    return _copy_val(_store.get(name))


def storeUpdate(name, f):
    if name in _store_busy:
        fail("「" + name + "」这个格子正在改，不能在改它的函数里再改它")
    _store_busy.add(name)
    try:
        v = _copy_val(f(storeRead(name)))
        _store[name] = v
        return _copy_val(v)
    finally:
        _store_busy.discard(name)


def run(main):
    failed = False
    try:
        main()
    except LcError as e:
        _out.append("出错：" + str(e))
        failed = True
    sys.stdout.buffer.write(("\n".join(_out) + "\n").encode("utf-8"))
    sys.stdout.buffer.flush()
    if failed:
        sys.exit(1)
''';
