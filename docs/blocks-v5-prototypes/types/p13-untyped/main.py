import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from typing import Any


def 平均(xs: list[int]) -> float:
    总: int = 0
    for x in xs:
        总 = lc.iadd(总, x)
    return lc.fdiv(float(总), float(len(xs)))


def 重复(s: str, n: int) -> str:
    out: str = ""
    for i in range(0, n):
        out = out + s
    return out


def 较大(a: float, b: int) -> float:
    if a > float(b):
        return a
    return float(b)


def 阶乘(n: int) -> int:
    if n <= 1:
        return 1
    return lc.imul(n, 阶乘(lc.isub(n, 1)))


def 随便(v: Any) -> str:
    return "[" + lc.dtext(v) + "]"


def main() -> None:
    lc.log("平均 " + lc.fmt_num(平均([1, 2, 4])))
    lc.log(重复("ab", 3))
    lc.log("较大 " + lc.fmt_num(较大(3.0, 7)))
    lc.log("较大 " + lc.fmt_num(较大(2.5, 1)))
    lc.log("阶乘 " + str(阶乘(10)))
    lc.log(随便(1.0))
    lc.log(随便("x"))
    lc.log(随便([1.0, 2.0]))
    lc.log("阶乘 " + str(阶乘(19)))


lc.run(main)
