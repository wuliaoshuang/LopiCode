package main

import "v5types/_prelude/lc"

func main() {
	lc.Run(func() {
		var a, b int64 = 7, 2
		x, y := 0.1, 0.2
		lc.Log("7/2=" + lc.FmtNum(lc.FDiv(float64(a), float64(b))))
		lc.Log("7整除2=" + lc.IntText(lc.IDiv(a, b)))
		lc.Log("-7整除2=" + lc.IntText(lc.IDiv(lc.ISub(0, a), b)))
		lc.Log("-7余2=" + lc.IntText(lc.IMod(lc.ISub(0, a), b)))
		lc.Log("7余-2=" + lc.IntText(lc.IMod(a, lc.ISub(0, b))))
		lc.Log("0.1+0.2=" + lc.FmtNum(x+y))
		lc.Log("a+x=" + lc.FmtNum(float64(a)+x))
		lc.Log("6/3=" + lc.FmtNum(lc.FDiv(6, 3)))
		var 大 int64 = 9007199254740991
		lc.Log("最大整数=" + lc.IntText(大))
		平均 := lc.FDiv(float64(lc.IAdd(a, b)), 2)
		lc.Log("平均=" + lc.FmtNum(平均))
		n := lc.FToI(x * 30)
		lc.Log("n=" + lc.IntText(n))
		f := 1e308
		lc.Log("太大=" + lc.FmtNum(f*10))
		if e, ok := lc.Try(func() { lc.Log("大+1=" + lc.IntText(lc.IAdd(大, 1))) }); !ok {
			lc.Log("接住：" + e)
		}
		if e, ok := lc.Try(func() { lc.Log("7整除0=" + lc.IntText(lc.IDiv(a, 0))) }); !ok {
			lc.Log("接住：" + e)
		}
		if e, ok := lc.Try(func() { lc.Log("x/0=" + lc.FmtNum(lc.FDiv(x, 0))) }); !ok {
			lc.Log("接住：" + e)
		}
		lc.Log("平方=" + lc.IntText(lc.IMul(94906267, 94906267)))
	})
}
