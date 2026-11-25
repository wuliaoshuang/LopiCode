package main

import "v5types/_prelude/lc"

func 找年龄(名单 map[string]int64, 名字 string) *int64 {
	return lc.Get(名单, 名字)
}

func 描述(岁 *int64) string {
	if 岁 == nil {
		return "不知道"
	}
	if *岁 >= 18 {
		return lc.IntText(*岁) + "岁，成年"
	}
	return lc.IntText(*岁) + "岁，未成年"
}

func main() {
	lc.Run(func() {
		var 名 string
		var v *int64
		名单 := map[string]int64{"小明": 12, "小红": 20}
		lc.Log(描述(找年龄(名单, "小明")))
		lc.Log(描述(找年龄(名单, "小红")))
		lc.Log(描述(找年龄(名单, "小刚")))
		岁 := lc.Get(名单, "小刚")
		lc.Log("默认：" + lc.IntText(lc.Or(岁, 0)))
		var 总 int64 = 0
		for _, 名 = range lc.ListOf("小明", "小红", "小刚").Items {
			v = lc.Get(名单, 名)
			if v != nil {
				总 = lc.IAdd(总, *v)
			}
		}
		lc.Log("总和：" + lc.IntText(总))
		var 首字 *string = nil
		if 岁 != nil && *岁 > 3 {
			首字 = lc.Some("大")
		} else {
			首字 = lc.Some("无")
		}
		lc.Log("首字：" + lc.Or(首字, "?"))
		lc.Log("硬取：" + lc.IntText(lc.Must(岁)))
	})
}
