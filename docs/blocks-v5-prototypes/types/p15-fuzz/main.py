import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from typing import Callable


def 下一个(x: int) -> int:
    return lc.imod(lc.imul(x, 48271), 2147483647)


def 搅(h: int, s: str) -> int:
    for ch in s:
        h = lc.imod(lc.iadd(lc.imul(h, 31), ord(ch)), 1000000007)
    return h


def 试算(f: Callable[[], str]) -> str:
    try:
        return f()
    except lc.LcError as e:
        return str(e)


def main() -> None:
    x: int = 20261125
    h1: int = 7
    h2: int = 7
    错: int = 0
    不同: int = 0
    for i in range(0, 2000):
        x = 下一个(x); a: int = lc.isub(lc.imod(x, 2000001), 1000000)
        x = 下一个(x); b: int = lc.isub(lc.imod(x, 41), 20)
        x = 下一个(x); p: float = lc.fdiv(float(lc.isub(lc.imod(x, 2000001), 1000000)), 997.0)
        x = 下一个(x); q: float = lc.fdiv(float(lc.isub(lc.imod(x, 20001), 10000)), 7.0)
        r1: str = 试算(lambda: str(lc.iadd(a, b)) + "," + str(lc.isub(a, b)) + "," + str(lc.imul(a, b)) + "," + str(lc.idiv(a, b)) + "," + str(lc.imod(a, b)) + "," + lc.fmt_num(lc.fdiv(float(a), float(b))) + "," + lc.fmt_num(p + q) + "," + lc.fmt_num(p - q) + "," + lc.fmt_num(p * q) + "," + lc.fmt_num(lc.fdiv(p, q)))
        fa, fb = float(a), float(b)
        r2: str = 试算(lambda: lc.dtext(lc.dadd(fa, fb)) + "," + lc.dtext(lc.dsub(fa, fb)) + "," + lc.dtext(lc.dmul(fa, fb)) + "," + lc.dtext(lc.didiv(fa, fb)) + "," + lc.dtext(lc.dimod(fa, fb)) + "," + lc.dtext(lc.ddiv(fa, fb)) + "," + lc.dtext(lc.dadd(p, q)) + "," + lc.dtext(lc.dsub(p, q)) + "," + lc.dtext(lc.dmul(p, q)) + "," + lc.dtext(lc.ddiv(p, q)))
        if r1 == "除以 0":
            错 = lc.iadd(错, 1)
        if r1 != r2:
            不同 = lc.iadd(不同, 1)
        h1 = 搅(h1, r1)
        h2 = 搅(h2, r2)
    lc.log("校验和（原生类型的路）" + str(h1))
    lc.log("校验和（任意的路）" + str(h2))
    lc.log("除以 0 的次数 " + str(错) + "，两条路不同的次数 " + str(不同))


lc.run(main)
