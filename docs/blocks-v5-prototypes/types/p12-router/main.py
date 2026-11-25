import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "_prelude"))
import lc
from dataclasses import dataclass, replace
from enum import Enum
from typing import Callable


class 方法(Enum):
    GET = "GET"
    POST = "POST"


@dataclass(frozen=True)
class 请求:
    方法: 方法
    路径: str
    内容: str


@dataclass(frozen=True)
class 响应:
    状态: int
    内容: str


type 处理 = Callable[[请求, dict[str, str]], 响应]


@dataclass(frozen=True)
class 路由:
    方法: 方法
    段: list[str]
    处理: 处理


class 路由器:
    def __init__(self) -> None:
        self.表: list[路由] = []
        self.中间件: list[Callable[[处理], 处理]] = []

    def 加(self, m: 方法, 路径: str, h: 处理) -> None:
        self.表.append(路由(m, 路径.split("/"), h))

    def 用(self, mw: Callable[[处理], 处理]) -> None:
        self.中间件.append(mw)

    def 匹配(self, 模: list[str], 实: list[str]) -> dict[str, str] | None:
        if len(模) != len(实):
            return None
        参: dict[str, str] = {}
        for i in range(0, len(模)):
            a: str = lc.at(模, i)
            b: str = lc.at(实, i)
            if a.startswith(":"):
                参[a[1 : len(a)]] = b
            elif a != b:
                return None
        return 参

    def 处理(self, req: 请求) -> 响应:
        实: list[str] = req.路径.split("/")
        for r in self.表:
            if r.方法 == req.方法:
                参: dict[str, str] | None = self.匹配(r.段, 实)
                if 参 is not None:
                    h: 处理 = r.处理
                    for mw in self.中间件:
                        h = mw(h)
                    return h(req, 参)
        return 响应(404, "没有这个地址：" + req.路径)


def main() -> None:
    app: 路由器 = 路由器()
    次数: int = 0

    def mw1(下一个: 处理) -> 处理:
        def f(req: 请求, 参: dict[str, str]) -> 响应:
            nonlocal 次数
            次数 = lc.iadd(次数, 1)
            return 下一个(req, 参)

        return f

    app.用(mw1)

    def mw2(下一个: 处理) -> 处理:
        def f(req: 请求, 参: dict[str, str]) -> 响应:
            res: 响应 = 下一个(req, 参)
            return replace(res, 内容=res.内容 + " ✓")

        return f

    app.用(mw2)
    app.加(方法.GET, "/hello/:name", lambda req, 参: 响应(200, "你好，" + (t if (t := 参.get("name")) is not None else "?")))

    def h2(req: 请求, 参: dict[str, str]) -> 响应:
        a: int | None = lc.parse_int(t if (t := 参.get("a")) is not None else "")
        b: int | None = lc.parse_int(t if (t := 参.get("b")) is not None else "")
        if a is None or b is None:
            return 响应(400, "要两个整数")
        return 响应(200, str(lc.iadd(a, b)) + " " + req.内容)

    app.加(方法.POST, "/sum/:a/:b", h2)
    for q in [请求(方法.GET, "/hello/小明", ""), 请求(方法.POST, "/sum/3/4", "ok"), 请求(方法.POST, "/sum/3/x", ""), 请求(方法.GET, "/nope", ""), 请求(方法.GET, "/sum/1/2", "")]:
        res: 响应 = app.处理(q)
        lc.log(str(res.状态) + " " + res.内容)
    lc.log("经过中间件 " + str(次数) + " 次")


lc.run(main)
