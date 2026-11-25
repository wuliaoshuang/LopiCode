package main

import "v5types/_prelude/lc"

// 记录 → struct（按值传，天然“改不了别人手里那份”）＋ 生成的 Eq
type 点 struct{ x, y float64 }

func (a 点) Eq(b 点) bool { return a.x == b.x && a.y == b.y }

type 用户 struct {
	名字 string
	年龄 int64
	位置 点
	昵称 *string
}

func (a 用户) Eq(b 用户) bool {
	return a.名字 == b.名字 && a.年龄 == b.年龄 && a.位置.Eq(b.位置) && ((a.昵称 == nil && b.昵称 == nil) || (a.昵称 != nil && b.昵称 != nil && *a.昵称 == *b.昵称))
}

func 搬家(u 用户, dx float64) 用户 {
	t1 := u.位置
	t1.x = u.位置.x + dx
	t2 := u
	t2.位置 = t1
	return t2
}

func 介绍(u 用户) string {
	return u.名字 + "(" + lc.IntText(u.年龄) + ") 在 " + lc.FmtNum(u.位置.x) + "," + lc.FmtNum(u.位置.y) + " 昵称:" + lc.Or(u.昵称, "无")
}

func main() {
	lc.Run(func() {
		a := 用户{名字: "小明", 年龄: 12, 位置: 点{x: 1, y: 2.5}, 昵称: nil}
		b := 搬家(a, 0.5)
		lc.Log(介绍(a))
		lc.Log(介绍(b))
		c := b
		c.昵称 = lc.Some("明明")
		lc.Log(介绍(c))
		t := a
		lc.Log("a等于a的拷贝 " + lc.BoolText(a.Eq(t)))
		lc.Log("a等于b " + lc.BoolText(a.Eq(b)))
		全部 := lc.ListOf(a, b, c)
		lc.Log("平均年龄 " + lc.FmtNum(lc.FDiv(float64(lc.Reduce(全部, int64(0), func(s int64, u 用户) int64 { return lc.IAdd(s, u.年龄) })), float64(全部.Len()))))
	})
}
