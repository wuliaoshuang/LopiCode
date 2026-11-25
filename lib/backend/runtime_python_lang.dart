/// Python 的语言核心小库（生成的工程里的 `lc_lang.py`）：积木第 4 版新加的操作。只有用到新积木的工程才带这个文件。
///
/// 函数表和规矩见 lib/lang/rt.dart 的 `kLangRtFns`；改这里的行为要同时改别的语言的
/// （`test/lang_conformance_test.dart` 让各语言跑同一批程序、比对输出是否逐字节相同）。
/// 注意：这个文件里定义了 `max`、`min`、`abs`、`round`、`pow`、`range`，会盖住 Python 自带的同名函数；文件里要用自带的那个写 `_b.xxx`。
library;

const String kPythonLangRuntimeSource = r'''
"""LopiCode 语言核心小库（Python）：积木第 4 版新加的操作——类型、数学、文字、列表、字典、JSON、数列。

值的规矩（数字化、文字化、等于…）在 lc_runtime.py 里；这里把它的函数也一起带上，生成的代码只认这一个文件。
每份生成的工程都一样，不用改。规矩：位置从 0 数；文字按 Unicode 码点算；读不到得空；写到不存在的位置抛错。
"""
import builtins as _b
import math
import random as _random
import re

import lc_runtime as _rt
from lc_runtime import *  # noqa: F401,F403  把值的规矩那一份的函数也带上
from lc_runtime import eq, to_json, to_num, to_text, truthy

RANGE_LIMIT = 10000  # “数列”“重复文字”最多这么多项
COUNT_LIMIT = 2147483647  # “从…数到…”最多数这么多遍

E_NOT_LIST = "这不是列表，改不了"
E_NOT_DICT = "这不是字典，改不了"
E_NO_ITEM = "列表里没有这个位置"
E_NOT_INDEXABLE = "这个值不能按位置或键来改"

_TYPE_NAMES = {"num": "number", "text": "text", "bool": "bool", "null": "null", "list": "list", "obj": "dict", "fn": "function"}
_HOLE = re.compile(r"\{([^{}]*)\}")
_LOWER = re.compile("[a-z]+")
_UPPER = re.compile("[A-Z]+")


class LcError(Exception):
    """积木运行时出的错（比如往列表里不存在的位置写）。"""


def _pz(n):
    """去掉“负零”（各语言写出来不一样）。"""
    return 0.0 if n == 0 else float(n)


def _is_list(x):
    return _rt._kind(x) == "list"


def _is_dict(x):
    return _rt._kind(x) == "obj"


def _index(i):
    return int(to_num(i))


def _clamp(n, lo, hi):
    return lo if n < lo else hi if n > hi else n


def _list(x):
    return x if _is_list(x) else []


# —— 类型 ——


def is_type(x, name):
    return _TYPE_NAMES[_rt._kind(x)] == to_text(name)


def to_number(x):
    return to_num(x)


def to_bool(x):
    return truthy(x)


def copy(x):
    if _is_list(x):
        return [copy(v) for v in x]
    if _is_dict(x):
        return {k: copy(v) for k, v in x.items()}
    return x


# —— 数学 ——


def pow(a, b):
    try:
        return _pz(_rt._fin(math.pow(to_num(a), to_num(b))))
    except (ValueError, OverflowError):
        return 0.0


def round(x):
    n = to_num(x)
    t = float(math.trunc(n))
    return _pz(t + (-1.0 if n < 0 else 1.0) if _b.abs(n - t) >= 0.5 else t)


def floor(x):
    return _pz(math.floor(to_num(x)))


def ceil(x):
    return _pz(math.ceil(to_num(x)))


def abs(x):
    return _b.abs(to_num(x))


def sqrt(x):
    n = to_num(x)
    return 0.0 if n < 0 else math.sqrt(n)


def max(a, b):
    x = to_num(a)
    y = to_num(b)
    return x if x >= y else y


def min(a, b):
    x = to_num(a)
    y = to_num(b)
    return x if x <= y else y


def random(a, b):
    x = _index(a)
    y = _index(b)
    lo = x if x <= y else y
    hi = y if x <= y else x
    return _pz(lo + math.floor(_random.random() * (hi - lo + 1)))


# —— 文字 ——


def char_at(s, i):
    text = to_text(s)
    n = _index(i)
    return text[n] if 0 <= n < len(text) else None


def substring(s, start, stop):
    text = to_text(s)
    a = _clamp(_index(start), 0, len(text))
    b = _clamp(_index(stop), 0, len(text))
    return "" if a >= b else text[a:b]


def contains(s, sub):
    return to_text(sub) in to_text(s)


def starts_with(s, p):
    return to_text(s).startswith(to_text(p))


def ends_with(s, p):
    return to_text(s).endswith(to_text(p))


def index_of(s, sub):
    return float(to_text(s).find(to_text(sub)))


def replace(s, old, new):
    f = to_text(old)
    return to_text(s) if f == "" else to_text(s).replace(f, to_text(new))


def split(s, sep):
    p = to_text(sep)
    return list(to_text(s)) if p == "" else to_text(s).split(p)


def trim(s):
    return to_text(s).strip(" \t\r\n")


def upper(s):
    return _LOWER.sub(lambda m: m.group().upper(), to_text(s))


def lower(s):
    return _UPPER.sub(lambda m: m.group().lower(), to_text(s))


def repeat_text(s, n):
    return to_text(s) * _clamp(_index(n), 0, RANGE_LIMIT)


def template(s, d):
    def fill(m):
        return to_text(d[m.group(1)]) if _is_dict(d) and m.group(1) in d else m.group(0)

    return _HOLE.sub(fill, to_text(s))


# —— 列表 ——


def list_of(*xs):
    return list(xs)


def list_get(xs, i):
    n = _index(i)
    return xs[n] if _is_list(xs) and 0 <= n < len(xs) else None


def list_set(xs, i, v):
    if not _is_list(xs):
        raise LcError(E_NOT_LIST)
    n = _index(i)
    if n < 0 or n >= len(xs):
        raise LcError(E_NO_ITEM)
    xs[n] = v


def list_push(xs, v):
    if not _is_list(xs):
        raise LcError(E_NOT_LIST)
    xs.append(v)


def list_insert(xs, i, v):
    if not _is_list(xs):
        raise LcError(E_NOT_LIST)
    n = _index(i)
    if n < 0 or n > len(xs):
        raise LcError(E_NO_ITEM)
    xs.insert(n, v)


def list_remove(xs, i):
    if not _is_list(xs):
        raise LcError(E_NOT_LIST)
    n = _index(i)
    if n < 0 or n >= len(xs):
        raise LcError(E_NO_ITEM)
    return xs.pop(n)


def list_pop(xs):
    return xs.pop() if _is_list(xs) and len(xs) > 0 else None


def list_index_of(xs, v):
    for i, x in enumerate(_list(xs)):
        if eq(x, v):
            return float(i)
    return -1.0


def list_contains(xs, v):
    return list_index_of(xs, v) >= 0


def list_slice(xs, start, stop):
    items = _list(xs)
    a = _clamp(_index(start), 0, len(items))
    b = _clamp(_index(stop), 0, len(items))
    return [] if a >= b else items[a:b]


def list_concat(a, b):
    return _list(a) + _list(b)


def list_reverse(xs):
    return _list(xs)[::-1]


def _sort_key(v):
    if _rt._kind(v) == "num":
        return (0, float(v), "")
    return (1, 0.0, to_text(v))


def list_sort(xs):
    """数字排在前面、按大小；其余的文字化后按码点。"""
    return sorted(_list(xs), key=_sort_key)


def list_join(xs, sep):
    return to_text(sep).join(to_text(x) for x in _list(xs))


def count_steps(start, stop, step):
    a = to_num(start)
    s = to_num(step)
    if s == 0:
        return 0
    d = (to_num(stop) - a) / s
    if not d >= 0:
        return 0
    if d >= COUNT_LIMIT:
        return COUNT_LIMIT
    n = math.floor(d + 1e-9) + 1
    return COUNT_LIMIT if n > COUNT_LIMIT else n


def range(start, stop, step):
    a = to_num(start)
    s = to_num(step)
    n = _b.min(count_steps(a, stop, s), RANGE_LIMIT)
    return [a + k * s for k in _b.range(n)]


# —— 字典 ——


def dict_of(*pairs):
    return {to_text(pairs[i]): pairs[i + 1] for i in _b.range(0, len(pairs) - 1, 2)}


def dict_has(d, k):
    return _is_dict(d) and to_text(k) in d


def dict_get(d, k):
    return d.get(to_text(k)) if _is_dict(d) else None


def dict_set(d, k, v):
    if not _is_dict(d):
        raise LcError(E_NOT_DICT)
    d[to_text(k)] = v


def dict_remove(d, k):
    if not _is_dict(d):
        raise LcError(E_NOT_DICT)
    d.pop(to_text(k), None)


def dict_keys(d):
    return sorted(d) if _is_dict(d) else []


def dict_values(d):
    return [d[k] for k in dict_keys(d)]


def dict_pairs(d):
    return [[k, d[k]] for k in dict_keys(d)]


def dict_merge(a, b):
    out = {}
    for d in (a, b):
        if _is_dict(d):
            out.update(d)
    return out


# —— 列表 / 字典 / 文字通用 ——


def item(x, k):
    if _is_list(x):
        return list_get(x, k)
    if _is_dict(x):
        return dict_get(x, k)
    return char_at(x, k) if isinstance(x, str) else None


def set_item(x, k, v):
    if _is_list(x):
        return list_set(x, k, v)
    if _is_dict(x):
        return dict_set(x, k, v)
    raise LcError(E_NOT_INDEXABLE)


# —— JSON ——


def from_json(s):
    try:
        return _rt._parse_body(to_text(s).encode("utf-8"))
    except UnicodeError:
        return None
''';
