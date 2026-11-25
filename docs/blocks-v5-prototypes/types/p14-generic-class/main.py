import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from typing import Callable


class 栈[T]:
    def __init__(self) -> None:
        self.项: list[T] = []

    def 压(self, x: T) -> None:
        self.项.append(x)

    def 弹(self) -> T | None:
        if len(self.项) == 0:
            return None
        x: T = lc.at(self.项, lc.isub(len(self.项), 1))
        self.项.pop()
        return x

    def 大小(self) -> int:
        return len(self.项)


class 状态[T]:
    def __init__(self, 初: T) -> None:
        self.听: list[Callable[[T, T], None]] = []
        self.值: T = 初

    def 读(self) -> T:
        return self.值

    def 订阅(self, f: Callable[[T, T], None]) -> None:
        self.听.append(f)

    def 写(self, 新值: T) -> None:
        旧: T = self.值
        self.值 = 新值
        for f in self.听:
            f(旧, 新值)


def main() -> None:
    s: 栈[int] = 栈()
    s.压(1)
    s.压(2)
    s.压(3)
    lc.log("弹 " + str(t if (t := s.弹()) is not None else -1) + " 剩 " + str(s.大小()))
    名: 栈[str] = 栈()
    名.压("a")
    lc.log("弹 " + (t2 if (t2 := 名.弹()) is not None else "?") + " 再弹 " + (t3 if (t3 := 名.弹()) is not None else "空了"))
    计数: 状态[int] = 状态(0)
    记: list[str] = []

    def f1(旧: int, 新值: int) -> None:
        记.append(str(旧) + "→" + str(新值))

    计数.订阅(f1)
    计数.写(lc.iadd(计数.读(), 1))
    计数.写(lc.imul(计数.读(), 10))
    lc.log(" ".join(记))
    标题: 状态[str] = 状态("你好")

    def f2(旧: str, 新值: str) -> None:
        lc.log("标题变了：" + 新值)

    标题.订阅(f2)
    标题.写("再见")


lc.run(main)
