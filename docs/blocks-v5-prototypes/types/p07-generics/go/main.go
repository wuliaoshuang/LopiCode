package main

import (
	"cmp"

	"v5types/_prelude/lc"
)

func 第一个[T any](xs *lc.List[T]) *T {
	if xs.Len() == 0 {
		return nil
	}
	return lc.Some(xs.At(0))
}

func 最大[T cmp.Ordered](xs *lc.List[T], 底 T) T {
	var x T
	m := 底
	for _, x = range xs.Items {
		if x > m {
			m = x
		}
	}
	return m
}

func 配对[K, V any](ks *lc.List[K], vs *lc.List[V], f func(K, V) string) *lc.List[string] {
	out := lc.ListOf[string]()
	for i := int64(0); i < ks.Len(); i++ {
		out.Push(f(ks.At(i), vs.At(i)))
	}
	return out
}

func main() {
	lc.Run(func() {
		lc.Log("第一个 " + lc.IntText(lc.Or(第一个(lc.ListOf[int64](3, 1, 2)), -1)))
		空表 := lc.ListOf[string]()
		lc.Log("空的第一个 " + lc.Or(第一个(空表), "没有"))
		lc.Log("最大整数 " + lc.IntText(最大(lc.ListOf[int64](3, 9, 2), 0)))
		lc.Log("最大小数 " + lc.FmtNum(最大(lc.ListOf(1.5, 0.25), 0)))
		lc.Log("最大文字 " + 最大(lc.ListOf("ｚ", "😀", "a"), ""))
		lc.Log(lc.Join(配对(lc.ListOf("a", "b"), lc.ListOf[int64](1, 2), func(k string, v int64) string { return k + "=" + lc.IntText(v) }), ";"))
	})
}
