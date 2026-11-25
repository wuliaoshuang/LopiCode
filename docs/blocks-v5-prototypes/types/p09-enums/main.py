import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from dataclasses import dataclass
from enum import Enum


class 灯(Enum):
    红 = "红"
    黄 = "黄"
    绿 = "绿"


@dataclass(frozen=True)
class 形状_圆:
    r: float


@dataclass(frozen=True)
class 形状_矩形:
    w: float
    h: float


@dataclass(frozen=True)
class 形状_点:
    pass


type 形状 = 形状_圆 | 形状_矩形 | 形状_点


def 下一个(l: 灯) -> 灯:
    match l:
        case 灯.红:
            return 灯.绿
        case 灯.绿:
            return 灯.黄
        case 灯.黄:
            return 灯.红
    raise AssertionError("到不了这里")


def 面积(s: 形状) -> float:
    match s:
        case 形状_圆(r):
            return 3.0 * (r * r)
        case 形状_矩形(w, h):
            return w * h
        case 形状_点():
            return 0.0
    raise AssertionError("到不了这里")


def main() -> None:
    l: 灯 = 灯.红
    for i in range(0, 4):
        lc.log(str(i) + ":" + l.value)
        l = 下一个(l)
    全: list[形状] = [形状_圆(1.0), 形状_矩形(2.0, 3.5), 形状_点()]
    for s in 全:
        lc.log("面积 " + lc.fmt_num(面积(s)))
    lc.log("红==红 " + lc.bool_text(l == 灯.红))
    match lc.at(全, 1):
        case 形状_矩形(w, h):
            lc.log("宽" + lc.fmt_num(w))
        case _:
            lc.log("不是矩形")


lc.run(main)
