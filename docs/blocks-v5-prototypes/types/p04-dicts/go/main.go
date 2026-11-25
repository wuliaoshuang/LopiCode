package main

import (
	"strings"

	"v5types/_prelude/lc"
)

func main() {
	lc.Run(func() {
		var w, k string
		var v int64
		词 := lc.ListOf("苹果", "香蕉", "苹果", "😀", "橙子", "香蕉", "苹果", "ｚ")
		数 := map[string]int64{}
		for _, w = range 词.Items {
			数[w] = lc.IAdd(lc.Or(lc.Get(数, w), 0), 1)
		}
		for _, k = range lc.Keys(数) {
			v = 数[k]
			lc.Log(k + "=" + lc.IntText(v))
		}
		lc.Log("共 " + lc.IntText(int64(len(数))) + " 种")
		_, has := 数["梨"]
		lc.Log("有梨吗 " + lc.BoolText(has))
		delete(数, "香蕉")
		lc.Log(strings.Join(lc.Keys(数), "|"))
	})
}
