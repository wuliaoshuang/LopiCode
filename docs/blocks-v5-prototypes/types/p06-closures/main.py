import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from typing import Callable


def 做计数器(步: int) -> Callable[[], int]:
    n: int = 0

    def f1() -> int:
        nonlocal n
        n = lc.iadd(n, 步)
        return n

    return f1


def 组合[A, B, C](f: Callable[[A], B], g: Callable[[B], C]) -> Callable[[A], C]:
    return lambda x: g(f(x))


def 做两次(f: Callable[[int], int], x: int) -> int:
    return f(f(x))


def main() -> None:
    c1: Callable[[], int] = 做计数器(1)
    c2: Callable[[], int] = 做计数器(10)
    c1()
    c1()
    lc.log("c1=" + str(c1()) + " c2=" + str(c2()))
    加一: Callable[[int], int] = lambda n: lc.iadd(n, 1)
    转文: Callable[[int], str] = lambda n: "<" + str(n) + ">"
    管: Callable[[int], str] = 组合(加一, 转文)
    lc.log(管(41))
    lc.log("两次 " + str(做两次(加一, 5)))
    动作: list[Callable[[int], int]] = [加一, lambda n: lc.imul(n, 2)]
    x: int = 3
    for f in 动作:
        x = f(x)
    lc.log("x=" + str(x))


lc.run(main)
