package main

import "v5types/_prelude/lc"

func main() {
	lc.Run(func() {
		数 := lc.ListOf[int64](1, 2, 3, 4, 5, 6)
		平方 := lc.Map(数, func(n int64) int64 { return lc.IMul(n, n) })
		偶 := lc.Filter(平方, func(n int64) bool { return lc.IMod(n, 2) == 0 })
		和 := lc.Reduce(偶, int64(0), func(acc int64, n int64) int64 { return lc.IAdd(acc, n) })
		半 := lc.Map(数, func(n int64) float64 { return lc.FDiv(float64(n), 2) })
		均 := lc.Reduce(半, float64(0), func(acc float64, h float64) float64 { return acc + h })
		词 := lc.Map(数, func(n int64) string { return "#" + lc.IntText(n) })
		空的 := lc.ListOf[float64]()
		空的.Push(2.5)
		空的.Push(1)
		lc.Log("平方 " + lc.Join(lc.Map(平方, func(n int64) string { return lc.IntText(n) }), ","))
		lc.Log("偶 " + lc.Join(lc.Map(偶, func(n int64) string { return lc.IntText(n) }), ","))
		lc.Log("和 " + lc.IntText(和))
		lc.Log("半 " + lc.Join(lc.Map(半, func(h float64) string { return lc.FmtNum(h) }), ","))
		lc.Log("均 " + lc.FmtNum(均))
		lc.Log("词 " + lc.Join(词, ","))
		lc.Log("空的 " + lc.Join(lc.Map(空的, func(h float64) string { return lc.FmtNum(h) }), ",") + " 长 " + lc.IntText(空的.Len()))
		lc.Log("第7项 " + lc.IntText(数.At(6)))
	})
}
