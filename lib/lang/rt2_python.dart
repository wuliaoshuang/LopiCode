/// 规矩版本 2 的小库·Python（`lc2.py`）。规矩见 docs/blocks-v5-parts/B-type-system.md 第 2、5、8、11 节；函数名和 Node 版一样。
///
/// 值在 Python 里的样子：整数＝int；小数＝float；文字＝str；是否＝bool；空＝None；列表＝list；字典＝dict（遍历按码点从小到大）；
/// 记录 / 变体 / 枚举 / 对象＝生成的 class（分别继承 Rec / Variant / Enum / Obj）；函数＝能调的东西。
/// “任意”里的数字一律是 float（整数装进“任意”时变成 float，取回成整数时检查）。
library;

const String kRt2PythonHead = r'''
# LopiCode 积木的小库（Python，严格规矩）。由 LopiCode 生成，别手改。
import builtins as _b
import copy as _copy
import json as _json
import math
import os as _os
import random as _random
import re as _re
import sys
import threading as _threading
import time as _time
import traceback as _traceback
import urllib.parse as _urlparse
from decimal import Context, Decimal, ROUND_HALF_UP

MAX = 9007199254740991
_R12 = Context(prec=12, rounding=ROUND_HALF_UP)
sys.setrecursionlimit(20000)


class LcError(Exception):
    # 抛出去的错：外面这层带着那句话；obj 是错误对象（小库自己报的错没有，接住的时候才按种类造）。
    def __init__(self, m, obj=None):
        super().__init__(m)
        self.obj = obj


_ERR_KINDS = (("除以 0", "数值不对"), ("整数超出范围", "数值不对"), ("变不成整数", "数值不对"), ("超出了", "找不到"), ("拿到的是", "类型不对"), ("值是空", "类型不对"))
_err_make = [None]


def errKind(m):
    for part, k in _ERR_KINDS:
        if part in m:
            return k
    return "错误"


def errSetup(f):
    _err_make[0] = f


def errObj(e):
    if e.obj is None:
        e.obj = _err_make[0](errKind(str(e)), str(e))
    return e.obj


def kindOf(x):
    return type(x).lcName


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

# —— 后端积木里早就有的那几个（严格规矩下的说法见 rt_v2.dart） ——
def _num_arg(name, x):
    if isinstance(x, bool) or not isinstance(x, (int, float)):
        fail("「" + name + "」要数字，拿到的是" + kind(x))
    return x


def abs(x):
    return _b.abs(_num_arg("绝对值", x))


def max(a, b):
    return a if _num_arg("较大的", a) >= _num_arg("较大的", b) else b


def min(a, b):
    return a if _num_arg("较小的", a) <= _num_arg("较小的", b) else b


def random(a, b):
    return _random.randint(_b.min(a, b), _b.max(a, b))


def copy(x):
    if isinstance(x, list):
        return [copy(v) for v in x]
    if isinstance(x, dict):
        return {k: copy(v) for k, v in x.items()}
    return x


def template(s, d):
    return _re.sub(r"\{([^{}]*)\}", lambda m: dtext(d[m.group(1)]) if m.group(1) in d else m.group(0), s)


def toBool(x):
    if x is None or x is False or x == "":
        return False
    return not (isinstance(x, (int, float)) and not isinstance(x, bool) and x == 0)


def listInsert(xs, i, v):
    if i < 0 or i > _b.len(xs):
        _out_of(i, _b.len(xs))
    xs.insert(i, v)


def listRemove(xs, i):
    if i < 0 or i >= _b.len(xs):
        _out_of(i, _b.len(xs))
    return xs.pop(i)


def listSort(xs):
    nums = all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in xs)
    if not nums and not all(isinstance(v, str) for v in xs):
        fail("排序要全是数字或者全是文字的列表，拿到的是混着的")
    return sorted(xs)


def dictPairs(d):
    return [[k, toDyn(d[k])] for k in keys(d)]
''';
