package main

import "v5types/_prelude/lc"

func 读用户(数据 any) string {
	d := lc.AsDict(数据)
	名 := lc.AsText(d["名字"])
	岁 := lc.AsInt(d["年龄"])
	标签 := lc.Map(lc.AsList(d["标签"]), func(t any) string { return lc.AsText(t) })
	return 名 + " " + lc.IntText(lc.IAdd(岁, 1)) + " " + lc.Join(标签, "/")
}

func main() {
	lc.Run(func() {
		var 坏 any
		var 好 any = map[string]any{"名字": "小明", "年龄": float64(12), "标签": lc.ListOf[any]("a", "b")}
		lc.Log(读用户(好))
		var n int64 = 41
		var 装 any = float64(n)
		lc.Log("装进再取出 " + lc.IntText(lc.IAdd(lc.AsInt(装), 1)))
		lc.Log("任意相加 " + lc.DText(lc.DAdd(装, 0.5)))
		lc.Log("任意的样子 " + lc.DText(好))
		for _, 坏 = range lc.ListOf[any](
			map[string]any{"名字": "小红", "年龄": "十二", "标签": lc.ListOf[any]()},
			map[string]any{"名字": float64(7)},
			map[string]any{"名字": "小刚", "年龄": 12.5, "标签": lc.ListOf[any]()},
			"不是字典",
			map[string]any{"名字": "小白", "年龄": float64(3), "标签": lc.ListOf[any](float64(1))},
		).Items {
			if e, ok := lc.Try(func() { lc.Log(读用户(坏)) }); !ok {
				lc.Log("不行：" + e)
			}
		}
	})
}
