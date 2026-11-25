import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from typing import Any


def 读用户(数据: Any) -> str:
    d: dict[str, Any] = lc.as_dict(数据)
    名: str = lc.as_text(d.get("名字"))
    岁: int = lc.as_int(d.get("年龄"))
    标签: list[str] = [lc.as_text(t) for t in lc.as_list(d.get("标签"))]
    return 名 + " " + str(lc.iadd(岁, 1)) + " " + "/".join(标签)


def main() -> None:
    好: Any = {"名字": "小明", "年龄": 12.0, "标签": ["a", "b"]}
    lc.log(读用户(好))
    n: int = 41
    装: Any = float(n)
    lc.log("装进再取出 " + str(lc.iadd(lc.as_int(装), 1)))
    lc.log("任意相加 " + lc.dtext(lc.dadd(装, 0.5)))
    lc.log("任意的样子 " + lc.dtext(好))
    坏: Any
    for 坏 in [
        {"名字": "小红", "年龄": "十二", "标签": []},
        {"名字": 7.0},
        {"名字": "小刚", "年龄": 12.5, "标签": []},
        "不是字典",
        {"名字": "小白", "年龄": 3.0, "标签": [1.0]},
    ]:
        try:
            lc.log(读用户(坏))
        except lc.LcError as err:
            e: str = str(err)
            lc.log("不行：" + e)


lc.run(main)
