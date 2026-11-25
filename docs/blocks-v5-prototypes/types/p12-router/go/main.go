package main

import (
	"strings"

	"v5types/_prelude/lc"
)

type 方法 int

const (
	方法GET 方法 = iota
	方法POST
)

type 请求 struct {
	方法 方法
	路径 string
	内容 string
}
type 响应 struct {
	状态 int64
	内容 string
}
type 处理 = func(请求, map[string]string) 响应
type 路由 struct {
	方法 方法
	段  *lc.List[string]
	处理 处理
}

type 路由器 struct {
	表   *lc.List[路由]
	中间件 *lc.List[func(处理) 处理]
}

func New路由器() *路由器 {
	o := &路由器{}
	o.表 = lc.ListOf[路由]()
	o.中间件 = lc.ListOf[func(处理) 处理]()
	return o
}
func (o *路由器) 加(m 方法, 路径 string, h 处理) {
	o.表.Push(路由{方法: m, 段: lc.Split(路径, "/"), 处理: h})
}
func (o *路由器) 用(mw func(处理) 处理) { o.中间件.Push(mw) }
func (o *路由器) 匹配(模 *lc.List[string], 实 *lc.List[string]) map[string]string {
	var a, b string
	if 模.Len() != 实.Len() {
		return nil
	}
	参 := map[string]string{}
	for i := int64(0); i < 模.Len(); i++ {
		a = 模.At(i)
		b = 实.At(i)
		if strings.HasPrefix(a, ":") {
			参[lc.Substr(a, 1, lc.TextLen(a))] = b
		} else if a != b {
			return nil
		}
	}
	return 参
}
func (o *路由器) 处理(req 请求) 响应 {
	var r 路由
	var 参 map[string]string
	var h 处理
	var mw func(处理) 处理
	实 := lc.Split(req.路径, "/")
	for _, r = range o.表.Items {
		if r.方法 == req.方法 {
			参 = o.匹配(r.段, 实)
			if 参 != nil {
				h = r.处理
				for _, mw = range o.中间件.Items {
					h = mw(h)
				}
				return h(req, 参)
			}
		}
	}
	return 响应{状态: 404, 内容: "没有这个地址：" + req.路径}
}

func main() {
	lc.Run(func() {
		var q 请求
		var res 响应
		app := New路由器()
		var 次数 int64 = 0
		app.用(func(下一个 处理) 处理 {
			return func(req 请求, 参 map[string]string) 响应 {
				次数 = lc.IAdd(次数, 1)
				return 下一个(req, 参)
			}
		})
		app.用(func(下一个 处理) 处理 {
			return func(req 请求, 参 map[string]string) 响应 {
				res := 下一个(req, 参)
				t := res
				t.内容 = res.内容 + " ✓"
				return t
			}
		})
		app.加(方法GET, "/hello/:name", func(req 请求, 参 map[string]string) 响应 {
			return 响应{状态: 200, 内容: "你好，" + lc.Or(lc.Get(参, "name"), "?")}
		})
		app.加(方法POST, "/sum/:a/:b", func(req 请求, 参 map[string]string) 响应 {
			a := lc.ParseInt(lc.Or(lc.Get(参, "a"), ""))
			b := lc.ParseInt(lc.Or(lc.Get(参, "b"), ""))
			if a == nil || b == nil {
				return 响应{状态: 400, 内容: "要两个整数"}
			}
			return 响应{状态: 200, 内容: lc.IntText(lc.IAdd(*a, *b)) + " " + req.内容}
		})
		for _, q = range lc.ListOf(请求{方法GET, "/hello/小明", ""}, 请求{方法POST, "/sum/3/4", "ok"}, 请求{方法POST, "/sum/3/x", ""}, 请求{方法GET, "/nope", ""}, 请求{方法GET, "/sum/1/2", ""}).Items {
			res = app.处理(q)
			lc.Log(lc.IntText(res.状态) + " " + res.内容)
		}
		lc.Log("经过中间件 " + lc.IntText(次数) + " 次")
	})
}
