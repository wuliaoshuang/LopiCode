import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc


def 找年龄(名单: dict[str, int], 名字: str) -> int | None:
    return 名单.get(名字)


def 描述(岁: int | None) -> str:
    if 岁 is None:
        return "不知道"
    if 岁 >= 18:
        return str(岁) + "岁，成年"
    return str(岁) + "岁，未成年"


def main() -> None:
    名单: dict[str, int] = {"小明": 12, "小红": 20}
    lc.log(描述(找年龄(名单, "小明")))
    lc.log(描述(找年龄(名单, "小红")))
    lc.log(描述(找年龄(名单, "小刚")))
    岁: int | None = 名单.get("小刚")
    lc.log("默认：" + str(岁 if 岁 is not None else 0))
    总: int = 0
    for 名 in ["小明", "小红", "小刚"]:
        v: int | None = 名单.get(名)
        if v is not None:
            总 = lc.iadd(总, v)
    lc.log("总和：" + str(总))
    首字: str | None = None
    if 岁 is not None and 岁 > 3:
        首字 = "大"
    else:
        首字 = "无"
    lc.log("首字：" + (首字 if 首字 is not None else "?"))
    lc.log("硬取：" + str(lc.must(岁)))


lc.run(main)
