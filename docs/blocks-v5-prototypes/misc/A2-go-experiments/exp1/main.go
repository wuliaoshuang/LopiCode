package main

import "fmt"

// ---- 写法一：只用结构体嵌入 ----
type Animal struct{ Name string }

func (a *Animal) Sound() string { return "……" }
func (a *Animal) Intro() string { return a.Name + " 叫：" + a.Sound() } // 父方法里调 Sound

type Dog struct{ Animal }

func (d *Dog) Sound() string { return "汪" } // “重写”

// ---- 写法二：嵌入 + 父里存一个接口类型的“自己” ----
type AnimalI interface {
	Sound() string
	Intro() string
}
type Animal2 struct {
	Name string
	self AnimalI // 指向最外层对象
}

func (a *Animal2) Sound() string { return "……" }
func (a *Animal2) Intro() string { return a.Name + " 叫：" + a.self.Sound() } // 经接口调

type Dog2 struct{ Animal2 }

func (d *Dog2) Sound() string { return "汪" }
func (d *Dog2) Intro() string { return "[狗] " + d.Animal2.Intro() } // 调父类版本

type Puppy2 struct{ Dog2 } // 三层

func (p *Puppy2) Sound() string { return "嘤" }

func NewAnimal2(n string) *Animal2 { a := &Animal2{Name: n}; a.self = a; return a }
func NewDog2(n string) *Dog2       { d := &Dog2{}; d.Name = n; d.self = d; return d }
func NewPuppy2(n string) *Puppy2   { p := &Puppy2{}; p.Name = n; p.self = p; return p }

func main() {
	d := &Dog{Animal{"阿黄"}}
	fmt.Println("写法一 直接调:", d.Sound())
	fmt.Println("写法一 父方法里:", d.Intro())
	var list []AnimalI = []AnimalI{NewAnimal2("某兽"), NewDog2("阿黄"), NewPuppy2("小黄")}
	for _, x := range list {
		fmt.Println("写法二:", x.Intro())
	}
	// 是…吗
	_, isDog := list[2].(interface{ Sound() string })
	_, isDog2 := list[2].(*Dog2)
	fmt.Println("小黄有Sound方法:", isDog, " 小黄是*Dog2:", isDog2)
}
