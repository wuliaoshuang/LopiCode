package main

import "v5types/_prelude/lc"

type 有面积 interface {
	面积() float64
	名字() string
}

// 不能被继承的类 → 普通 struct，用指针
type 圆 struct{ r float64 }

func New圆(r float64) *圆     { o := &圆{}; o.r = r; return o }
func (o *圆) 面积() float64   { return 3 * (o.r * o.r) }
func (o *圆) 名字() string    { return "圆" }

type 方 struct{ a float64 }

func New方(a float64) *方     { o := &方{}; o.a = a; return o }
func (o *方) 面积() float64   { return o.a * o.a }
func (o *方) 名字() string    { return "方" }

// 可以被继承的类 → 一个接口（变量的类型）＋ 一个“体”（放字段）。体里的 self 指回最外面那个对象，
// 这样父类方法里“让自己叫”会叫到子类重写的那个。
type 动物 interface {
	叫声() string
	介绍() string
	as动物() *动物体
}
type 动物体 struct {
	self 动物
	名    string
	腿    int64
}

func (o *动物体) init(名 string) { o.腿 = 4; o.名 = 名 }
func New动物(名 string) *动物体   { o := &动物体{}; o.self = o; o.init(名); return o }
func (o *动物体) as动物() *动物体  { return o }
func (o *动物体) 叫声() string   { return "…" }
func (o *动物体) 介绍() string {
	return o.名 + "说" + o.self.叫声() + "，" + lc.IntText(o.腿) + "条腿"
}

type 狗 struct{ 动物体 }

func New狗(名 string) *狗   { o := &狗{}; o.self = o; o.动物体.init(名); return o }
func (o *狗) 叫声() string { return "汪" }

type 鸟 interface {
	动物
	as鸟() *鸟体
}
type 鸟体 struct{ 动物体 }

func (o *鸟体) init(名 string) { o.动物体.init(名); o.腿 = 2 }
func New鸟(名 string) *鸟体   { o := &鸟体{}; o.self = o; o.init(名); return o }
func (o *鸟体) as鸟() *鸟体    { return o }
func (o *鸟体) 叫声() string  { return "啾" + o.动物体.叫声() }

func 总面积(xs *lc.List[有面积]) float64 {
	return lc.Reduce(xs, float64(0), func(s float64, x 有面积) float64 { return s + x.面积() })
}

func main() {
	lc.Run(func() {
		var s 有面积
		var p 动物
		形 := lc.ListOf[有面积](New圆(1), New方(2))
		for _, s = range 形.Items {
			lc.Log(s.名字() + " " + lc.FmtNum(s.面积()))
		}
		lc.Log("总面积 " + lc.FmtNum(总面积(形)))
		宠 := lc.ListOf[动物](New狗("旺财"), New鸟("啾啾"), New动物("某只"))
		for _, p = range 宠.Items {
			lc.Log(p.介绍())
		}
		d := 宠.At(0)
		if _, ok := d.(*狗); ok {
			lc.Log("第一只是狗")
		}
		_, is鸟 := d.(鸟)
		lc.Log("是鸟吗 " + lc.BoolText(is鸟))
	})
}
