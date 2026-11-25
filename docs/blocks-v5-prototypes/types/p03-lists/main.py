import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from functools import reduce


def main() -> None:
    数: list[int] = [1, 2, 3, 4, 5, 6]
    平方: list[int] = [lc.imul(n, n) for n in 数]
    偶: list[int] = [n for n in 平方 if lc.imod(n, 2) == 0]
    和: int = reduce(lambda acc, n: lc.iadd(acc, n), 偶, 0)
    半: list[float] = [lc.fdiv(float(n), 2.0) for n in 数]
    均: float = reduce(lambda acc, h: acc + h, 半, 0.0)
    词: list[str] = ["#" + str(n) for n in 数]
    空的: list[float] = []
    空的.append(2.5)
    空的.append(1.0)
    lc.log("平方 " + ",".join(str(n) for n in 平方))
    lc.log("偶 " + ",".join(str(n) for n in 偶))
    lc.log("和 " + str(和))
    lc.log("半 " + ",".join(lc.fmt_num(h) for h in 半))
    lc.log("均 " + lc.fmt_num(均))
    lc.log("词 " + ",".join(词))
    lc.log("空的 " + ",".join(lc.fmt_num(h) for h in 空的) + " 长 " + str(len(空的)))
    lc.log("第7项 " + str(lc.at(数, 6)))


lc.run(main)
