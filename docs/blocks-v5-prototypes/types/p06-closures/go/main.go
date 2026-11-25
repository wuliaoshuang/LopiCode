package main

import "v5types/_prelude/lc"

func 做计数器(步 int64) func() int64 {
	var n int64 = 0
	return func() int64 {
		n = lc.IAdd(n, 步)
		return n
	}
}

func 组合[A, B, C any](f func(A) B, g func(B) C) func(A) C {
	return func(x A) C { return g(f(x)) }
}

func 做两次(f func(int64) int64, x int64) int64 {
	return f(f(x))
}

func main() {
	lc.Run(func() {
		var f func(int64) int64
		c1 := 做计数器(1)
		c2 := 做计数器(10)
		c1()
		c1()
		lc.Log("c1=" + lc.IntText(c1()) + " c2=" + lc.IntText(c2()))
		加一 := func(n int64) int64 { return lc.IAdd(n, 1) }
		转文 := func(n int64) string { return "<" + lc.IntText(n) + ">" }
		管 := 组合(加一, 转文)
		lc.Log(管(41))
		lc.Log("两次 " + lc.IntText(做两次(加一, 5)))
		动作 := lc.ListOf(加一, func(n int64) int64 { return lc.IMul(n, 2) })
		var x int64 = 3
		for _, f = range 动作.Items {
			x = f(x)
		}
		lc.Log("x=" + lc.IntText(x))
	})
}
