package main

import "v5types/_prelude/lc"

type 灯 int

const (
	灯红 灯 = iota
	灯黄
	灯绿
)

func (l 灯) Text() string { return [...]string{"红", "黄", "绿"}[l] }

type 形状 interface{ is形状() }
type 形状圆 struct{ r float64 }
type 形状矩形 struct{ w, h float64 }
type 形状点 struct{}

func (形状圆) is形状()  {}
func (形状矩形) is形状() {}
func (形状点) is形状()  {}

func 下一个(l 灯) 灯 {
	switch l {
	case 灯红:
		return 灯绿
	case 灯绿:
		return 灯黄
	case 灯黄:
		return 灯红
	}
	panic("到不了这里")
}

func 面积(s 形状) float64 {
	switch v := s.(type) {
	case 形状圆:
		r := v.r
		return 3 * (r * r)
	case 形状矩形:
		w, h := v.w, v.h
		return w * h
	case 形状点:
		return 0
	}
	panic("到不了这里")
}

func main() {
	lc.Run(func() {
		var s 形状
		l := 灯红
		for i := int64(0); i < 4; i++ {
			lc.Log(lc.IntText(i) + ":" + l.Text())
			l = 下一个(l)
		}
		全 := lc.ListOf[形状](形状圆{1}, 形状矩形{2, 3.5}, 形状点{})
		for _, s = range 全.Items {
			lc.Log("面积 " + lc.FmtNum(面积(s)))
		}
		lc.Log("红==红 " + lc.BoolText(l == 灯红))
		switch v := 全.At(1).(type) {
		case 形状矩形:
			w := v.w
			lc.Log("宽" + lc.FmtNum(w))
		default:
			lc.Log("不是矩形")
		}
	})
}
