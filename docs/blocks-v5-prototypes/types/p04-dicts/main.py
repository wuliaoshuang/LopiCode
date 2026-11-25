import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc


def main() -> None:
    词: list[str] = ["苹果", "香蕉", "苹果", "😀", "橙子", "香蕉", "苹果", "ｚ"]
    数: dict[str, int] = {}
    for w in 词:
        t = 数.get(w)
        数[w] = lc.iadd(t if t is not None else 0, 1)
    for k in lc.keys(数):
        v: int = 数[k]
        lc.log(k + "=" + str(v))
    lc.log("共 " + str(len(数)) + " 种")
    lc.log("有梨吗 " + lc.bool_text("梨" in 数))
    数.pop("香蕉", None)
    lc.log("|".join(lc.keys(数)))


lc.run(main)
