package main

import "v5types/_prelude/lc"

func 下一个(x int64) int64 { return lc.IMod(lc.IMul(x, 48271), 2147483647) }

func 搅(h int64, s string) int64 {
	for _, c := range s {
		h = lc.IMod(lc.IAdd(lc.IMul(h, 31), int64(c)), 1000000007)
	}
	return h
}

func 试算(f func() string) (r string) {
	if e, ok := lc.Try(func() { r = f() }); !ok {
		return e
	}
	return r
}

func main() {
	lc.Run(func() {
		var x, h1, h2, 错, 不同 int64 = 20261125, 7, 7, 0, 0
		for i := int64(0); i < 2000; i++ {
			x = 下一个(x)
			a := lc.ISub(lc.IMod(x, 2000001), 1000000)
			x = 下一个(x)
			b := lc.ISub(lc.IMod(x, 41), 20)
			x = 下一个(x)
			p := lc.FDiv(float64(lc.ISub(lc.IMod(x, 2000001), 1000000)), 997)
			x = 下一个(x)
			q := lc.FDiv(float64(lc.ISub(lc.IMod(x, 20001), 10000)), 7)
			r1 := 试算(func() string {
				return lc.IntText(lc.IAdd(a, b)) + "," + lc.IntText(lc.ISub(a, b)) + "," + lc.IntText(lc.IMul(a, b)) + "," + lc.IntText(lc.IDiv(a, b)) + "," + lc.IntText(lc.IMod(a, b)) + "," + lc.FmtNum(lc.FDiv(float64(a), float64(b))) + "," + lc.FmtNum(p+q) + "," + lc.FmtNum(p-q) + "," + lc.FmtNum(p*q) + "," + lc.FmtNum(lc.FDiv(p, q))
			})
			var fa, fb, ap, aq any = float64(a), float64(b), p, q
			r2 := 试算(func() string {
				return lc.DText(lc.DAdd(fa, fb)) + "," + lc.DText(lc.DSub(fa, fb)) + "," + lc.DText(lc.DMul(fa, fb)) + "," + lc.DText(lc.DIDiv(fa, fb)) + "," + lc.DText(lc.DIMod(fa, fb)) + "," + lc.DText(lc.DDiv(fa, fb)) + "," + lc.DText(lc.DAdd(ap, aq)) + "," + lc.DText(lc.DSub(ap, aq)) + "," + lc.DText(lc.DMul(ap, aq)) + "," + lc.DText(lc.DDiv(ap, aq))
			})
			if r1 == "除以 0" {
				错 = lc.IAdd(错, 1)
			}
			if r1 != r2 {
				不同 = lc.IAdd(不同, 1)
			}
			h1 = 搅(h1, r1)
			h2 = 搅(h2, r2)
		}
		lc.Log("校验和（原生类型的路）" + lc.IntText(h1))
		lc.Log("校验和（任意的路）" + lc.IntText(h2))
		lc.Log("除以 0 的次数 " + lc.IntText(错) + "，两条路不同的次数 " + lc.IntText(不同))
	})
}
