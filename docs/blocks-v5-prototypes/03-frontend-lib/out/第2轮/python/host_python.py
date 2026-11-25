"""03 第 2 轮的前端假宿主（Python）：只有“调度”和“写到错误输出”。接口清单见 natives.json。
Python 没有“微任务”：攒着的事放进一个队列，等 tick.wait 或者程序的“启动时”全做完才跑。"""
import sys

import lc_lang as lc

_queue = []


def tick_defer(fn):
    _queue.append(fn)
    return None


def _drain():
    while _queue:
        fn = _queue.pop(0)
        try:
            lc.call(fn)
        except Exception as e:  # 攒着做的事出的错不让程序停
            sys.stderr.write("攒着做的事出错：" + str(e) + "\n")


def tick_wait():
    _drain()
    return None


def log_error(x):
    sys.stderr.write(lc.to_text(x) + "\n")
    sys.stderr.flush()
    return None


def ready():
    _drain()
