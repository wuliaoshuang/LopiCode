package main

import "v5types/_prelude/lc"

func main() {
	lc.Run(func() {
		xs := lc.ListOf[int64](1, 2, 3)
		var 装 any = lc.DynList(xs, lc.IntDyn)
		xs.Push(4)
		lc.Log("原来的有 " + lc.IntText(xs.Len()) + " 项，装进任意的是 " + lc.DText(装))
		动 := lc.AsList(装)
		动.Push("五")
		lc.Log("任意里的 " + lc.DText(装))
		if e, ok := lc.Try(func() {
			lc.ListFrom(装, lc.AsInt)
			lc.Log("到不了这里")
		}); !ok {
			lc.Log("不行：" + e)
		}
		动.Pop()
		回 := lc.ListFrom(装, lc.AsInt)
		回.Push(9)
		lc.Log("取回来的 " + lc.Join(lc.Map(回, func(n int64) string { return lc.IntText(n) }), ",") + "，任意里的 " + lc.DText(装) + "，原来的有 " + lc.IntText(xs.Len()) + " 项")
		d := map[string]float64{"a": 1.5}
		var 装2 any = lc.DynDict(d, lc.FloatDyn)
		d["b"] = 2
		lc.Log("字典 " + lc.DText(装2) + "，原来的有 " + lc.IntText(int64(len(d))) + " 项")
	})
}
