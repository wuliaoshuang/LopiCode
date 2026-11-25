package main

import "v5types/_prelude/lc"

// Go 没有 try：“试着做”翻成 lc.Try(闭包)；闭包里的“返回”先记在 ret / done 里，出了闭包再真的返回；
// “最后”翻成 defer（它在返回值定下来之后、函数真正结束之前跑）。
func 安全除(a int64, b int64) (ret string) {
	defer func() { lc.Log("算完一次") }()
	done := false
	e, ok := lc.Try(func() {
		ret, done = lc.IntText(a)+"/"+lc.IntText(b)+"="+lc.IntText(lc.IDiv(a, b)), true
	})
	if !ok {
		return lc.IntText(a) + "/" + lc.IntText(b) + " 不行：" + e
	}
	if done {
		return ret
	}
	panic("到不了这里")
}

func 取款(余额 int64, 要取 int64) int64 {
	if 要取 > 余额 {
		lc.Fail("余额不够，还差 " + lc.IntText(lc.ISub(要取, 余额)))
	}
	return lc.ISub(余额, 要取)
}

func main() {
	lc.Run(func() {
		lc.Log(安全除(7, 2))
		lc.Log(安全除(7, 0))
		var 钱 int64 = 100
		if e, ok := lc.Try(func() {
			钱 = 取款(钱, 30)
			钱 = 取款(钱, 100)
			lc.Log("到不了这里")
		}); !ok {
			lc.Log("接住：" + e + " 还剩 " + lc.IntText(钱))
		}
		xs := lc.ListOf[int64](1, 2, 3)
		if e, ok := lc.Try(func() { xs.Set(5, 9) }); !ok {
			lc.Log(e)
		}
		if e2, ok := lc.Try(func() {
			if e, ok := lc.Try(func() { lc.Fail("里层") }); !ok {
				lc.Fail(e + "→外层")
			}
		}); !ok {
			lc.Log(e2)
		}
		lc.Log("结果 " + lc.IntText(取款(1, 2)))
	})
}
