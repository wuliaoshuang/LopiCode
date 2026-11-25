/// Python 语言核心小库里“函数”那一部分（积木第 4 版·第 2 阶段）：函数值、调用、拿函数当参数的 8 个列表操作。
/// 接在 `kPythonLangRuntimeSource` 后面，同一个文件（`lc_lang.py`）。规矩见 lib/lang/rt.dart；五种语言要一起改。
library;

const String kPythonLangFuncSource = r'''
# —— 函数（第 2 阶段）——
# 函数值就是 Python 的函数，身上多记三样：名字、最少 / 最多收几个参数（最多是 -1＝不限）。

E_NOT_FUNCTION = "这不是函数，不能调用"
E_ARG_COUNT = "调用函数时给的参数个数对不上"


def fn(name, lo, hi, impl):
    impl.lc_name = name
    impl.lc_min = lo
    impl.lc_max = hi
    return impl


def _need_fn(f):
    if not callable(f) or not hasattr(f, "lc_min"):
        raise LcError(E_NOT_FUNCTION)


def call(f, *args):
    """调一个函数值：不是函数、参数个数对不上 → 抛错。没有返回值的函数得空。"""
    _need_fn(f)
    if len(args) < f.lc_min or (f.lc_max >= 0 and len(args) > f.lc_max):
        raise LcError(E_ARG_COUNT)
    return f(*args)


def _each(xs, f):
    """开始时把列表抄一份再走：回调里改了原来的列表也不影响这一趟。"""
    _need_fn(f)
    return list(_list(xs))


def list_map(xs, f):
    return [call(f, x) for x in _each(xs, f)]


def list_filter(xs, f):
    return [x for x in _each(xs, f) if truthy(call(f, x))]


def list_reduce(xs, f, init):
    acc = init
    for x in _each(xs, f):
        acc = call(f, acc, x)
    return acc


def list_find(xs, f):
    for x in _each(xs, f):
        if truthy(call(f, x)):
            return x
    return None


def list_every(xs, f):
    for x in _each(xs, f):
        if not truthy(call(f, x)):
            return False
    return True


def list_some(xs, f):
    for x in _each(xs, f):
        if truthy(call(f, x)):
            return True
    return False


def list_each(xs, f):
    for x in _each(xs, f):
        call(f, x)


def list_sort_by(xs, f):
    """按 f(项) 给的分从小到大：分是数字的排前面、按大小；其余的文字化后按码点；一样的保持原来的先后。"""
    keyed = [(_sort_key(call(f, x)), x) for x in _each(xs, f)]
    keyed.sort(key=lambda p: p[0])
    return [p[1] for p in keyed]
''';
