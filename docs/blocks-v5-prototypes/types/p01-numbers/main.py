import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc


def main() -> None:
    a: int = 7
    b: int = 2
    x: float = 0.1
    y: float = 0.2
    lc.log("7/2=" + lc.fmt_num(lc.fdiv(float(a), float(b))))
    lc.log("7整除2=" + str(lc.idiv(a, b)))
    lc.log("-7整除2=" + str(lc.idiv(lc.isub(0, a), b)))
    lc.log("-7余2=" + str(lc.imod(lc.isub(0, a), b)))
    lc.log("7余-2=" + str(lc.imod(a, lc.isub(0, b))))
    lc.log("0.1+0.2=" + lc.fmt_num(x + y))
    lc.log("a+x=" + lc.fmt_num(float(a) + x))
    lc.log("6/3=" + lc.fmt_num(lc.fdiv(6.0, 3.0)))
    大: int = 9007199254740991
    lc.log("最大整数=" + str(大))
    平均: float = lc.fdiv(float(lc.iadd(a, b)), 2.0)
    lc.log("平均=" + lc.fmt_num(平均))
    n: int = lc.ftoi(x * 30.0)
    lc.log("n=" + str(n))
    f: float = 1e308
    lc.log("太大=" + lc.fmt_num(f * 10.0))
    try:
        lc.log("大+1=" + str(lc.iadd(大, 1)))
    except lc.LcError as err:
        e: str = str(err)
        lc.log("接住：" + e)
    try:
        lc.log("7整除0=" + str(lc.idiv(a, 0)))
    except lc.LcError as err:
        e = str(err)
        lc.log("接住：" + e)
    try:
        lc.log("x/0=" + lc.fmt_num(lc.fdiv(x, 0.0)))
    except lc.LcError as err:
        e = str(err)
        lc.log("接住：" + e)
    lc.log("平方=" + str(lc.imul(94906267, 94906267)))


lc.run(main)
