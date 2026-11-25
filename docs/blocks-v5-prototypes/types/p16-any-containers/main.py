import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from typing import Any


def main() -> None:
    xs: list[int] = [1, 2, 3]
    装: Any = lc.to_dyn(xs)
    xs.append(4)
    lc.log("原来的有 " + str(len(xs)) + " 项，装进任意的是 " + lc.dtext(装))
    动: list[Any] = lc.as_list(装)
    动.append("五")
    lc.log("任意里的 " + lc.dtext(装))
    try:
        lc.as_list_of(装, lc.as_int)
        lc.log("到不了这里")
    except lc.LcError as err:
        e: str = str(err)
        lc.log("不行：" + e)
    动.pop()
    回: list[int] = lc.as_list_of(装, lc.as_int)
    回.append(9)
    lc.log("取回来的 " + ",".join(str(n) for n in 回) + "，任意里的 " + lc.dtext(装) + "，原来的有 " + str(len(xs)) + " 项")
    d: dict[str, float] = {"a": 1.5}
    装2: Any = lc.to_dyn(d)
    d["b"] = 2.0
    lc.log("字典 " + lc.dtext(装2) + "，原来的有 " + str(len(d)) + " 项")


lc.run(main)
