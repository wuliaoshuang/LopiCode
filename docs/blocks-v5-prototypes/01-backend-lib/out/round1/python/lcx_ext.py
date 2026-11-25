"""lcx 原型的“核心补充”（Python）：和 lcx_ext.js 一一对应，说明见那边。"""
import concurrent.futures
import math
import re
import sys
import traceback

import lc_lang as lc
import lc_runtime as _rt
from lc_lang import LcError


class Obj:
    """所有用“类”造出来的东西的共同祖先。"""

    def __init__(lc_self):
        pass


class Err(Obj, Exception):
    """内置的“错误”类（GAP-F1-01）：一个字段“消息”。自定义错误继承它。"""

    def __init__(lc_self, message=""):
        Obj.__init__(lc_self)
        lc_self.f_消息 = lc.to_text(message)
        Exception.__init__(lc_self, lc_self.f_消息)


def named(cls, name):
    cls.lc_name = name


named(Obj, "对象")
named(Err, "错误")


def sig(method, lo, hi):
    method.lc_min = lo
    method.lc_max = hi


def getf(o, name):
    if not isinstance(o, Obj) or ("f_" + name) not in o.__dict__:
        raise LcError("这个值没有“" + name + "”这个字段")
    return o.__dict__["f_" + name]


def setf(o, name, value):
    if not isinstance(o, Obj) or ("f_" + name) not in o.__dict__:
        raise LcError("这个值没有“" + name + "”这个字段")
    o.__dict__["f_" + name] = value


def send(o, name, *args):
    f = getattr(o, "m_" + name, None) if isinstance(o, Obj) else None
    if not callable(f):
        raise LcError("这个值没有“" + name + "”这个方法")
    if len(args) < f.lc_min or (f.lc_max >= 0 and len(args) > f.lc_max):
        raise LcError("调用方法时给的参数个数对不上")
    return f(*args)


def to_err(x):
    return x if isinstance(x, Err) else Err(lc.to_text(x))


def caught(e):
    if isinstance(e, Err):
        return e
    if isinstance(e, LcError):
        return Err(str(e))
    return Err("运行时内部出错")


_pool = concurrent.futures.ThreadPoolExecutor(max_workers=16)


def spawn(body):
    """“开始做”：马上开始、不等它。得到“稍后的结果”（Python 里是线程池的 Future）。"""
    return _pool.submit(body)


def await_(x):
    """“等”：是“稍后的结果”就等到它做完（它里面抛的错在这里抛出来），别的值原样。"""
    return x.result() if isinstance(x, concurrent.futures.Future) else x


def die(e):
    err = caught(e)
    sys.stderr.write("没接住的错误：" + err.f_消息 + "\n")
    if not isinstance(e, Err):
        traceback.print_exception(type(e), e, e.__traceback__)
    sys.stderr.flush()
    sys.exit(1)


def run(start):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass
    try:
        start()
    except Exception as e:  # 没接住的错误
        die(e)


# —— 被迫加的标准库函数 ——

_NUM = re.compile(r"[ \t\r\n]*[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?[ \t\r\n]*")


def is_numeric(x):
    """GAP-F1-07：是不是一个数字。"""
    if isinstance(x, bool):
        return False
    if isinstance(x, (int, float)):
        return True
    return isinstance(x, str) and _NUM.fullmatch(x) is not None and math.isfinite(float(x))


def or_else(a, b):
    """GAP-F1-08：第一个是空就用第二个。"""
    return b if a is None else a


def type_name(x):
    """GAP-F1-05：值的种类名。"""
    if isinstance(x, Err):
        return "error"
    if isinstance(x, Obj):
        return "object"
    if isinstance(x, concurrent.futures.Future):
        return "future"
    return {"num": "number", "text": "text", "bool": "bool", "null": "null", "list": "list", "obj": "dict", "fn": "function"}[_rt._kind(x)]
