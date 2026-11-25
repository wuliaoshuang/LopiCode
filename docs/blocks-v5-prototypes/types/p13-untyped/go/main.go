package main

import "v5types/_prelude/lc"

func 平均(xs *lc.List[int64]) float64 {
	var x int64
	var 总 int64 = 0
	for _, x = range xs.Items {
		总 = lc.IAdd(总, x)
	}
	return lc.FDiv(float64(总), float64(xs.Len()))
}

func 重复(s string, n int64) string {
	out := ""
	for i := int64(0); i < n; i++ {
		out = out + s
	}
	return out
}

func 较大(a float64, b int64) float64 {
	if a > float64(b) {
		return a
	}
	return float64(b)
}

func 阶乘(n int64) int64 {
	if n <= 1 {
		return 1
	}
	return lc.IMul(n, 阶乘(lc.ISub(n, 1)))
}

func 随便(v any) string {
	return "[" + lc.DText(v) + "]"
}

func main() {
	lc.Run(func() {
		lc.Log("平均 " + lc.FmtNum(平均(lc.ListOf[int64](1, 2, 4))))
		lc.Log(重复("ab", 3))
		lc.Log("较大 " + lc.FmtNum(较大(3, 7)))
		lc.Log("较大 " + lc.FmtNum(较大(2.5, 1)))
		lc.Log("阶乘 " + lc.IntText(阶乘(10)))
		lc.Log(随便(float64(1)))
		lc.Log(随便("x"))
		lc.Log(随便(lc.ListOf[any](float64(1), float64(2))))
		lc.Log("阶乘 " + lc.IntText(阶乘(19)))
	})
}
