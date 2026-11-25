import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from functools import reduce
from typing import Protocol


class 有面积(Protocol):
    def 面积(self) -> float: ...
    def 名字(self) -> str: ...


class 圆:
    def __init__(self, r: float) -> None:
        self.r: float = r

    def 面积(self) -> float:
        return 3.0 * (self.r * self.r)

    def 名字(self) -> str:
        return "圆"


class 方:
    def __init__(self, a: float) -> None:
        self.a: float = a

    def 面积(self) -> float:
        return self.a * self.a

    def 名字(self) -> str:
        return "方"


class 动物:
    def __init__(self, 名: str) -> None:
        self.腿: int = 4
        self.名: str = 名

    def 叫声(self) -> str:
        return "…"

    def 介绍(self) -> str:
        return self.名 + "说" + self.叫声() + "，" + str(self.腿) + "条腿"


class 狗(动物):
    def __init__(self, 名: str) -> None:
        super().__init__(名)

    def 叫声(self) -> str:
        return "汪"


class 鸟(动物):
    def __init__(self, 名: str) -> None:
        super().__init__(名)
        self.腿 = 2

    def 叫声(self) -> str:
        return "啾" + super().叫声()


def 总面积(xs: list[有面积]) -> float:
    return reduce(lambda s, x: s + x.面积(), xs, 0.0)


def main() -> None:
    形: list[有面积] = [圆(1.0), 方(2.0)]
    for s in 形:
        lc.log(s.名字() + " " + lc.fmt_num(s.面积()))
    lc.log("总面积 " + lc.fmt_num(总面积(形)))
    宠: list[动物] = [狗("旺财"), 鸟("啾啾"), 动物("某只")]
    for p in 宠:
        lc.log(p.介绍())
    d: 动物 = lc.at(宠, 0)
    if isinstance(d, 狗):
        lc.log("第一只是狗")
    lc.log("是鸟吗 " + lc.bool_text(isinstance(d, 鸟)))


lc.run(main)
