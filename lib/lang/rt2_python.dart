/// 规矩版本 2 的小库·Python（`lc2.py`）。规矩见 docs/blocks-v5-parts/B-type-system.md 第 2、5、8、11 节；函数名和 Node 版一样。
///
/// 值在 Python 里的样子：整数＝int；小数＝float；文字＝str；是否＝bool；空＝None；列表＝list；字典＝dict（遍历按码点从小到大）；
/// 记录 / 变体 / 枚举 / 对象＝生成的 class（分别继承 Rec / Variant / Enum / Obj）；函数＝能调的东西。
/// “任意”里的数字一律是 float（整数装进“任意”时变成 float，取回成整数时检查）。
library;

const String kRt2PythonSource = r'''
# LopiCode 积木的小库（Python，严格规矩）。由 LopiCode 生成，别手改。
import builtins as _b
import copy as _copy
import json as _json
import math
import re as _re
import sys
import time as _time
from decimal import Context, Decimal, ROUND_HALF_UP

MAX = 9007199254740991
_R12 = Context(prec=12, rounding=ROUND_HALF_UP)
sys.setrecursionlimit(20000)


class LcError(Exception):
    pass


class Rec:
    pass


class Variant(Rec):
    pass


class Enum:
    def __init__(self, name, index):
        self.name = name
        self.index = index


class Obj:
    pass


def fail(m):
    raise LcError(m)


def fmtNum(v):
    v = float(v)
    if math.isnan(v):
        return "不是数"
    if math.isinf(v):
        return "无穷大" if v > 0 else "-无穷大"
    if v == 0:
        return "0"
    if v == math.floor(v) and abs(v) <= MAX:
        return str(int(v))
    sign, dt, exponent = _R12.create_decimal(Decimal(v)).as_tuple()
    e = _b.len(dt) - 1 + exponent
    digits = "".join(str(d) for d in dt).rstrip("0")
    minus = "-" if sign else ""
    if e >= 15 or e < -7:
        return minus + digits[0] + ("." + digits[1:] if _b.len(digits) > 1 else "") + "e" + str(e)
    if e >= _b.len(digits) - 1:
        return minus + digits + "0" * (e - _b.len(digits) + 1)
    if e >= 0:
        return minus + digits[: e + 1] + "." + digits[e + 1 :]
    return minus + "0." + "0" * (-e - 1) + digits


def itext(n):
    return str(n)


def boolText(b):
    return "true" if b else "false"


# —— 整数、小数 ——
def _chk(r):
    return r if -MAX <= r <= MAX else fail("整数超出范围")


def iadd(a, b):
    return _chk(a + b)


def isub(a, b):
    return _chk(a - b)


def imul(a, b):
    return _chk(a * b)


def idiv(a, b):
    if b == 0:
        fail("除以 0")
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def imod(a, b):
    if b == 0:
        fail("除以 0")
    r = abs(a) % abs(b)
    return -r if a < 0 else r


def fdiv(a, b):
    return fail("除以 0") if b == 0 else a / b


def fpow(a, b):
    try:
        return math.pow(a, b)
    except OverflowError:
        return -math.inf if a < 0 and b == math.floor(b) and b % 2 == 1 else math.inf
    except ValueError:
        return math.inf if a == 0 else math.nan


def toInt(x):
    if not math.isfinite(x) or abs(math.trunc(x)) > MAX:
        fail("这个小数变不成整数：" + fmtNum(x))
    return math.trunc(x)


def floor(x):
    return toInt(math.floor(x) if math.isfinite(x) else x)


def ceil(x):
    return toInt(math.ceil(x) if math.isfinite(x) else x)


def round(x):
    if not math.isfinite(x):
        return toInt(x)
    t = math.trunc(x)
    return toInt(t + (-1 if x < 0 else 1) if abs(x - t) >= 0.5 else t)


def sqrt(x):
    return math.sqrt(x) if x >= 0 else math.nan


def now():
    return float(math.floor(_time.time() * 1000))


def steps(a, b, s):
    if s == 0 or (b - a) * s < 0:
        return 0
    return (b - a) // s + 1


def fsteps(a, b, s):
    if s == 0:
        return 0
    d = (b - a) / s
    if not d >= 0:
        return 0
    return MAX if math.isinf(d) else min(math.floor(d + 1e-9) + 1, MAX)


# —— 文字（按码点） ——
_WS = "\t\n\v\f\r \u00a0\u1680\u2000\u2001\u2002\u2003\u2004\u2005\u2006\u2007\u2008\u2009\u200a\u2028\u2029\u202f\u205f\u3000\ufeff"


def textLen(s):
    return _b.len(s)


def cmpText(a, b):
    return -1 if a < b else (1 if a > b else 0)


def _clamp(i, n):
    return 0 if i < 0 else (n if i > n else i)


def substring(s, a, b):
    a = _clamp(a, _b.len(s))
    b = _clamp(b, _b.len(s))
    return "" if a >= b else s[a:b]


def charAt(s, i):
    return s[i] if 0 <= i < _b.len(s) else fail("位置 " + str(i) + " 超出了文字的范围（共 " + str(_b.len(s)) + " 个字）")


def codePoints(s):
    return [ord(c) for c in s]


def split(s, sep):
    return list(s) if sep == "" else s.split(sep)


def startsWith(s, p):
    return s.startswith(p)


def endsWith(s, p):
    return s.endswith(p)


def contains(s, p):
    return p in s


def indexOf(s, p):
    return s.find(p)


def replace(s, a, b):
    return s if a == "" else s.replace(a, b)


def trim(s):
    return s.strip(_WS)


def upper(s):
    return s.upper()


def lower(s):
    return s.lower()


def repeatText(s, n):
    return "" if n <= 0 else s * n


def parseInt(s):
    if not _re.fullmatch(r"-?[0-9]+", s) or _b.len(s) > 20:
        return None
    n = int(s)
    return n if -MAX <= n <= MAX else None


# —— 这个值是什么 ——
def _isnum(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def kind(x):
    if x is None:
        return "空"
    if isinstance(x, bool):
        return "是否"
    if isinstance(x, (int, float)):
        return "数字"
    if isinstance(x, str):
        return "文字"
    if isinstance(x, list):
        return "列表"
    if isinstance(x, dict):
        return "字典"
    if isinstance(x, (Rec, Enum, Obj)):
        return "「" + getattr(type(x), "lcName", "对象") + "」"
    return "函数" if callable(x) else "「对象」"


def _want(name, x):
    fail("这里要" + name + "，拿到的是" + kind(x))


def asNum(x):
    return float(x) if _isnum(x) else _want("小数", x)


def asInt(x):
    if not _isnum(x):
        _want("整数", x)
    if isinstance(x, float) and (not math.isfinite(x) or x != math.floor(x)) or abs(x) > MAX:
        fail("这里要整数，拿到的是 " + fmtNum(x))
    return int(x)


def asText(x):
    return x if isinstance(x, str) else _want("文字", x)


def asBool(x):
    return x if isinstance(x, bool) else _want("是否", x)


def asFn(x):
    return x if callable(x) and not isinstance(x, (Rec, Enum, Obj, type)) else _want("函数", x)


def asList(x):
    return x if isinstance(x, list) else _want("列表", x)


def asDict(x):
    return x if isinstance(x, dict) else _want("字典", x)


def asOpt(x, f):
    return None if x is None else f(x)


def asA(x, tp, name):
    return x if isinstance(x, tp) else _want("「" + name + "」", x)


def isKind(x, name):
    return isinstance(x, Obj) and name in getattr(type(x), "lcKinds", ())


def asKind(x, name):
    return x if isKind(x, name) else _want("「" + name + "」", x)


def widenOpt(x):
    return None if x is None else float(x)


def _inside(where, f, v):
    try:
        return f(v)
    except LcError as e:
        fail(where + "：" + str(e))


def asListOf(x, f):
    return [_inside("列表的位置 " + str(i), f, v) for i, v in enumerate(asList(x))]


def asDictOf(x, f):
    asDict(x)
    return {k: _inside("字典的「" + k + "」", f, x[k]) for k in keys(x)}


def toDyn(x):
    if isinstance(x, list):
        return [toDyn(v) for v in x]
    if isinstance(x, dict):
        return {k: toDyn(v) for k, v in x.items()}
    if isinstance(x, int) and not isinstance(x, bool):
        return float(x)
    return x


# —— 相等、比大小 ——
def eq(a, b):
    if a is b:
        return True
    if a is None or b is None:
        return False
    if isinstance(a, bool) or isinstance(b, bool):
        return isinstance(a, bool) and isinstance(b, bool) and a == b
    if _isnum(a) or _isnum(b):
        return _isnum(a) and _isnum(b) and a == b
    if isinstance(a, str) or isinstance(b, str):
        return isinstance(a, str) and isinstance(b, str) and a == b
    if isinstance(a, list):
        return isinstance(b, list) and _b.len(a) == _b.len(b) and all(eq(v, b[i]) for i, v in enumerate(a))
    if isinstance(a, dict):
        return isinstance(b, dict) and _b.len(a) == _b.len(b) and all(k in b and eq(v, b[k]) for k, v in a.items())
    if isinstance(a, Rec):
        return type(a) is type(b) and all(eq(v, getattr(b, k)) for k, v in vars(a).items())
    return False


def cmp(a, b):
    return -1 if a < b else (1 if a > b else 0)


def dcmp(a, b):
    if (_isnum(a) and _isnum(b)) or (isinstance(a, str) and isinstance(b, str)):
        return cmp(a, b)
    fail("比大小的两边要都是数字或者都是文字，拿到的是" + kind(a) + "和" + kind(b))


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


def run(main):
    try:
        main()
    except LcError as e:
        _out.append("出错：" + str(e))
    sys.stdout.buffer.write(("\n".join(_out) + "\n").encode("utf-8"))
''';
