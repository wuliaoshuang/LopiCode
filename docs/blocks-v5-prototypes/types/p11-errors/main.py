import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc


def 安全除(a: int, b: int) -> str:
    try:
        return str(a) + "/" + str(b) + "=" + str(lc.idiv(a, b))
    except lc.LcError as err:
        e: str = str(err)
        return str(a) + "/" + str(b) + " 不行：" + e
    finally:
        lc.log("算完一次")


def 取款(余额: int, 要取: int) -> int:
    if 要取 > 余额:
        lc.fail("余额不够，还差 " + str(lc.isub(要取, 余额)))
    return lc.isub(余额, 要取)


def main() -> None:
    lc.log(安全除(7, 2))
    lc.log(安全除(7, 0))
    钱: int = 100
    try:
        钱 = 取款(钱, 30)
        钱 = 取款(钱, 100)
        lc.log("到不了这里")
    except lc.LcError as err:
        e: str = str(err)
        lc.log("接住：" + e + " 还剩 " + str(钱))
    xs: list[int] = [1, 2, 3]
    try:
        lc.set_at(xs, 5, 9)
    except lc.LcError as err:
        e = str(err)
        lc.log(e)
    try:
        try:
            lc.fail("里层")
        except lc.LcError as err:
            e = str(err)
            lc.fail(e + "→外层")
    except lc.LcError as err:
        e2: str = str(err)
        lc.log(e2)
    lc.log("结果 " + str(取款(1, 2)))


lc.run(main)
