"""类型原型用的“小库”（Python 版）。只为验证类型设计，不是产品代码。"""
import math
import sys
from decimal import Context, Decimal, ROUND_HALF_UP

MAX = 9007199254740991
_R12 = Context(prec=12, rounding=ROUND_HALF_UP)


class LcError(Exception):
    pass


def fail(m):
    raise LcError(m)


def fmt_num(v):
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
    e = len(dt) - 1 + exponent
    digits = "".join(str(d) for d in dt).rstrip("0")
    minus = "-" if sign else ""
    if e >= 15 or e < -7:
        return minus + digits[0] + ("." + digits[1:] if len(digits) > 1 else "") + "e" + str(e)
    if e >= len(digits) - 1:
        return minus + digits + "0" * (e - len(digits) + 1)
    if e >= 0:
        return minus + digits[: e + 1] + "." + digits[e + 1 :]
    return minus + "0." + "0" * (-e - 1) + digits


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


def ftoi(x):
    if not math.isfinite(x) or abs(math.trunc(x)) > MAX:
        fail("这个小数变不成整数：" + fmt_num(x))
    return math.trunc(x)


def text_len(s):
    return len(s)


def cmp(a, b):
    return -1 if a < b else (1 if a > b else 0)


def _range_msg(i, n):
    return "位置 " + str(i) + " 超出了列表的范围（共 " + str(n) + " 项）"


def at(xs, i):
    return xs[i] if 0 <= i < len(xs) else fail(_range_msg(i, len(xs)))


def set_at(xs, i, v):
    if 0 <= i < len(xs):
        xs[i] = v
    else:
        fail(_range_msg(i, len(xs)))


def keys(d):
    return sorted(d.keys())


def must(x):
    return fail("这里的值是空，不能直接用") if x is None else x


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
    if callable(x):
        return "函数"
    return "对象"


def _want(name, x):
    fail("这里要" + name + "，拿到的是" + kind(x))


def as_num(x):
    return float(x) if kind(x) == "数字" else _want("小数", x)


def as_int(x):
    if kind(x) != "数字":
        _want("整数", x)
    if x != math.floor(x) or abs(x) > MAX:
        fail("这里要整数，拿到的是 " + fmt_num(x))
    return int(x)


def as_text(x):
    return x if isinstance(x, str) else _want("文字", x)


def as_bool(x):
    return x if isinstance(x, bool) else _want("是否", x)


def as_list(x):
    return x if isinstance(x, list) else _want("列表", x)


def as_dict(x):
    return x if isinstance(x, dict) else _want("字典", x)


def _dnum(op, x):
    return float(x) if kind(x) == "数字" else fail(op + "的两边要数字，拿到的是" + kind(x))


def dadd(a, b):
    return _dnum("加法", a) + _dnum("加法", b)


def dsub(a, b):
    return _dnum("减法", a) - _dnum("减法", b)


def dmul(a, b):
    return _dnum("乘法", a) * _dnum("乘法", b)


def didiv(a, b):
    return float(idiv(as_int(a), as_int(b)))


def dimod(a, b):
    return float(imod(as_int(a), as_int(b)))


def ddiv(a, b):
    return fdiv(_dnum("除法", a), _dnum("除法", b))


def dtext(x):
    k = kind(x)
    if k == "空":
        return ""
    if k == "是否":
        return "true" if x else "false"
    if k == "数字":
        return fmt_num(x)
    if k == "文字":
        return x
    if k == "列表":
        return "[" + ",".join(djson(v) for v in x) + "]"
    if k == "字典":
        return "{" + ",".join('"' + key + '":' + djson(x[key]) for key in keys(x)) + "}"
    return "[" + k + "]"


def djson(x):
    k = kind(x)
    return "null" if k == "空" else ('"' + x + '"' if k == "文字" else dtext(x))


def bool_text(b):
    return "true" if b else "false"


def parse_int(s):
    import re
    if not re.fullmatch(r"-?[0-9]+", s):
        return None
    n = int(s)
    return n if -MAX <= n <= MAX else None


def to_dyn(x):
    if isinstance(x, list):
        return [to_dyn(v) for v in x]
    if isinstance(x, dict):
        return {k: to_dyn(v) for k, v in x.items()}
    if isinstance(x, int) and not isinstance(x, bool):
        return float(x)
    return x


def as_list_of(x, f):
    out = []
    for i, v in enumerate(as_list(x)):
        try:
            out.append(f(v))
        except LcError as e:
            fail("列表的位置 " + str(i) + "：" + str(e))
    return out


_out = []


def log(s):
    _out.append(s)


def run(main):
    try:
        main()
    except LcError as e:
        _out.append("出错：" + str(e))
    sys.stdout.buffer.write(("\n".join(_out) + "\n").encode("utf-8"))
