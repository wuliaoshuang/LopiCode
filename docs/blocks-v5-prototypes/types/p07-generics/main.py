import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from typing import Callable


def 第一个[T](xs: list[T]) -> T | None:
    if len(xs) == 0:
        return None
    return lc.at(xs, 0)


def 最大[T: (int, float, str)](xs: list[T], 底: T) -> T:
    m: T = 底
    for x in xs:
        if x > m:
            m = x
    return m


def 配对[K, V](ks: list[K], vs: list[V], f: Callable[[K, V], str]) -> list[str]:
    out: list[str] = []
    for i in range(0, len(ks)):
        out.append(f(lc.at(ks, i), lc.at(vs, i)))
    return out


def main() -> None:
    t1 = 第一个([3, 1, 2])
    lc.log("第一个 " + str(t1 if t1 is not None else -1))
    空表: list[str] = []
    t2 = 第一个(空表)
    lc.log("空的第一个 " + (t2 if t2 is not None else "没有"))
    lc.log("最大整数 " + str(最大([3, 9, 2], 0)))
    lc.log("最大小数 " + lc.fmt_num(最大([1.5, 0.25], 0.0)))
    lc.log("最大文字 " + 最大(["ｚ", "😀", "a"], ""))
    lc.log(";".join(配对(["a", "b"], [1, 2], lambda k, v: k + "=" + str(v))))


lc.run(main)
