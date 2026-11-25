package main

import "v5types/_prelude/lc"

type 栈[T any] struct{ 项 *lc.List[T] }

func New栈[T any]() *栈[T] { o := &栈[T]{}; o.项 = lc.ListOf[T](); return o }
func (o *栈[T]) 压(x T)    { o.项.Push(x) }
func (o *栈[T]) 弹() *T {
	if o.项.Len() == 0 {
		return nil
	}
	x := o.项.At(lc.ISub(o.项.Len(), 1))
	o.项.Pop()
	return lc.Some(x)
}
func (o *栈[T]) 大小() int64 { return o.项.Len() }

type 状态[T any] struct {
	值 T
	听 *lc.List[func(T, T)]
}

func New状态[T any](初 T) *状态[T] {
	o := &状态[T]{}
	o.听 = lc.ListOf[func(T, T)]()
	o.值 = 初
	return o
}
func (o *状态[T]) 读() T            { return o.值 }
func (o *状态[T]) 订阅(f func(T, T)) { o.听.Push(f) }
func (o *状态[T]) 写(新值 T) {
	var f func(T, T)
	旧 := o.值
	o.值 = 新值
	for _, f = range o.听.Items {
		f(旧, 新值)
	}
}

func main() {
	lc.Run(func() {
		s := New栈[int64]()
		s.压(1)
		s.压(2)
		s.压(3)
		lc.Log("弹 " + lc.IntText(lc.Or(s.弹(), -1)) + " 剩 " + lc.IntText(s.大小()))
		名 := New栈[string]()
		名.压("a")
		lc.Log("弹 " + lc.Or(名.弹(), "?") + " 再弹 " + lc.Or(名.弹(), "空了"))
		计数 := New状态[int64](0)
		记 := lc.ListOf[string]()
		计数.订阅(func(旧 int64, 新值 int64) { 记.Push(lc.IntText(旧) + "→" + lc.IntText(新值)) })
		计数.写(lc.IAdd(计数.读(), 1))
		计数.写(lc.IMul(计数.读(), 10))
		lc.Log(lc.Join(记, " "))
		标题 := New状态("你好")
		标题.订阅(func(旧 string, 新值 string) { lc.Log("标题变了：" + 新值) })
		标题.写("再见")
	})
}
