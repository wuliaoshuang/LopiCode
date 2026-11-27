/// 规矩版本 2 的小库·Python·“要等的事”那一块（拼在 `lc2.py` 里，见 rt2_python_dyn.dart）：这条线、等一会儿、开始做、等、
/// 等最多 / 等全部 / 等最先的一个、取消、一次只让一个做。规矩见 docs/blocks-v5-parts/B-gen-notes.md 第 16 节。只用 Python 自带的模块。
library;

const String kRt2PythonTask = r'''
# —— 要等的事：一件事一条线 ——
# “这条线”：一件事（主程序、一次“开始做”、一个请求）。记在线程自己的小本子上，取消、“一次只让一个做”靠它认。
class _Line:
    __slots__ = ("cancelled",)

    def __init__(self):
        self.cancelled = False


_tls = _threading.local()
_main_line = _Line()
_CANCEL = "这件事被取消了"
# 所有“要等”的地方共用一把锁：有一件事做完、被取消、有人从“一次只让一个做”里出来，就把在等的都叫醒，各自再看一眼。
_cv = _threading.Condition()


def _line():
    return getattr(_tls, "line", None) or _main_line


def _new_line():
    _tls.line = _Line()


def _line_check():
    with _cv:
        gone = _line().cancelled
    if gone:
        fail(_CANCEL)


# 等到 ready() 说行。这条线被取消＝先做 quit（有的话）再抛“取消了”；过了 deadline＝交回 False。
def _block(ready, deadline=None, quit=None):
    me = _line()
    with _cv:
        while True:
            if me.cancelled:
                if quit is not None:
                    quit()
                fail(_CANCEL)
            if ready():
                return True
            if deadline is None:
                _cv.wait()
            else:
                left = deadline - _time.monotonic()
                if left <= 0:
                    return False
                _cv.wait(left)


def hostSleep(ms):
    _block(lambda: False, _time.monotonic() + _b.max(0, ms) / 1000.0)


# “开始做”的结果。出了错先记着，等它的时候再抛。
class Task:
    def __init__(self, f):
        self.done = False
        self.val = None
        self.err = None
        self.line = _Line()
        _threading.Thread(target=self._run, args=(f,), daemon=True).start()

    def _run(self, f):
        _tls.line = self.line
        try:
            self.val = f()
        except BaseException as e:
            self.err = e
        finally:
            with _cv:
                self.done = True
                _cv.notify_all()

    def get(self):
        if self.err is not None:
            raise self.err
        return self.val


def spawn(f):
    return Task(f)


def wait(t):
    _block(lambda: t.done)
    return t.get()


# 最多等 ms 毫秒；到时候还没做完＝“超时”错误（那件事自己接着做）。
def awaitMax(t, ms):
    ms = _b.max(0, ms)
    if not _block(lambda: t.done, _time.monotonic() + ms / 1000.0):
        fail("等了 " + _b.str(ms) + " 毫秒还没做完")
    return t.get()


def cancel(t):
    with _cv:
        if not t.done and not t.line.cancelled:
            t.line.cancelled = True
            _cv.notify_all()


# 全做完才交回（结果按列表的顺序）。有一件出了错，或者等的人自己被取消了＝把还没做完的都取消，把错抛出去。
def awaitAll(tasks):
    ts = _b.list(tasks)
    bad = []

    def ready():
        every = True
        for t in ts:
            if not t.done:
                every = False
            elif t.err is not None:
                bad.append(t)
                return True
        return every

    try:
        _block(ready)
    except BaseException:
        for t in ts:
            cancel(t)
        raise
    if bad:
        for t in ts:
            cancel(t)
        raise bad[0].err
    return [t.val for t in ts]


# 谁先做完（成了或者出错）就用谁的；别的接着做。
def awaitAny(tasks):
    ts = _b.list(tasks)
    if not ts:
        fail("“等最先的一个”的列表是空的")
    first = []

    def ready():
        for t in ts:
            if t.done:
                first.append(t)
                return True
        return False

    _block(ready)
    return first[0].get()


def cancelled():
    with _cv:
        return _line().cancelled


# —— 一次只让一个做：按名字。别人在里面＝排队（先来先进）；自己已经在里面＝出错（不然会自己等自己）——
_gates = {}


def lockEnter(name):
    me = _line()
    with _cv:
        g = _gates.setdefault(name, [None, []])
        if g[0] is me:
            fail("「" + name + "」已经在“一次只让一个做”里面了，不能在里面再进一次")
        g[1].append(me)

    def ready():
        if g[0] is None and g[1][0] is me:
            g[0] = me
            g[1].pop(0)
            return True
        return False

    def quit():
        g[1].remove(me)
        _cv.notify_all()

    _block(ready, None, quit)
    return name


def lockLeave(name):
    me = _line()
    with _cv:
        g = _gates.get(name)
        if g is not None and g[0] is me:
            g[0] = None
            _cv.notify_all()


''';
