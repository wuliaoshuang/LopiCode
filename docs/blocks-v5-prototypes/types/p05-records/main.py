import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from dataclasses import dataclass, replace
from functools import reduce


@dataclass(frozen=True, eq=False)
class 点:
    x: float
    y: float

    def __eq__(self, o: object) -> bool:
        return isinstance(o, 点) and self.x == o.x and self.y == o.y


@dataclass(frozen=True, eq=False)
class 用户:
    名字: str
    年龄: int
    位置: 点
    昵称: str | None

    def __eq__(self, o: object) -> bool:
        return isinstance(o, 用户) and self.名字 == o.名字 and self.年龄 == o.年龄 and self.位置 == o.位置 and self.昵称 == o.昵称


def 搬家(u: 用户, dx: float) -> 用户:
    return replace(u, 位置=replace(u.位置, x=u.位置.x + dx))


def 介绍(u: 用户) -> str:
    return u.名字 + "(" + str(u.年龄) + ") 在 " + lc.fmt_num(u.位置.x) + "," + lc.fmt_num(u.位置.y) + " 昵称:" + (u.昵称 if u.昵称 is not None else "无")


def main() -> None:
    a: 用户 = 用户("小明", 12, 点(1.0, 2.5), None)
    b: 用户 = 搬家(a, 0.5)
    lc.log(介绍(a))
    lc.log(介绍(b))
    c: 用户 = replace(b, 昵称="明明")
    lc.log(介绍(c))
    lc.log("a等于a的拷贝 " + lc.bool_text(a == replace(a)))
    lc.log("a等于b " + lc.bool_text(a == b))
    全部: list[用户] = [a, b, c]
    lc.log("平均年龄 " + lc.fmt_num(lc.fdiv(float(reduce(lambda s, u: lc.iadd(s, u.年龄), 全部, 0)), float(len(全部)))))


lc.run(main)
