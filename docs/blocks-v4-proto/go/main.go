package main

import "fmt"

// 动态模式：对象 = 类（方法表，可有父类）+ 字段表；方法按名字找，找不到去父类找。
type Fn func(args ...any) any
type Class struct {
	name    string
	parent  *Class
	methods map[string]func(self *Obj, args ...any) any
}
type Obj struct {
	class  *Class
	fields map[string]any
}

func find(c *Class, name string) (func(self *Obj, args ...any) any, *Class) {
	for k := c; k != nil; k = k.parent {
		if m, ok := k.methods[name]; ok {
			return m, k
		}
	}
	panic("没有这个方法：" + name)
}
func call(o *Obj, name string, args ...any) any { m, _ := find(o.class, name); return m(o, args...) }
func super(o *Obj, from *Class, name string, args ...any) any {
	m, _ := find(from.parent, name)
	return m(o, args...)
}
func try(body func() any, handler func(msg string) any) (out any) {
	defer func() {
		if r := recover(); r != nil {
			out = handler(fmt.Sprint(r))
		}
	}()
	return body()
}

var Router = &Class{name: "Router", methods: map[string]func(self *Obj, args ...any) any{}}
var LoggingRouter = &Class{name: "LoggingRouter", parent: Router, methods: map[string]func(self *Obj, args ...any) any{}}

func init() {
	Router.methods["init"] = func(self *Obj, args ...any) any { self.fields["routes"] = []any{}; return nil }
	Router.methods["on"] = func(self *Obj, args ...any) any {
		self.fields["routes"] = append(self.fields["routes"].([]any), map[string]any{"method": args[0], "path": args[1], "handler": args[2]})
		return nil
	}
	Router.methods["handle"] = func(self *Obj, args ...any) any {
		for _, it := range self.fields["routes"].([]any) {
			r := it.(map[string]any)
			if r["method"] == args[0] && r["path"] == args[1] {
				return try(func() any { return r["handler"].(Fn)(map[string]any{"path": args[1]}) }, func(msg string) any { return "500 " + msg })
			}
		}
		return "404"
	}
	LoggingRouter.methods["handle"] = func(self *Obj, args ...any) any {
		out := super(self, LoggingRouter, "handle", args...)
		fmt.Println(fmt.Sprint(args[0]) + " " + fmt.Sprint(args[1]) + " -> " + fmt.Sprint(out))
		return out
	}
}
func newObj(c *Class, args ...any) *Obj {
	o := &Obj{class: c, fields: map[string]any{}}
	call(o, "init", args...)
	return o
}
func makeCounter() Fn {
	var n any = 0.0
	return func(args ...any) any { n = n.(float64) + 1; return n }
}
func main() {
	app := newObj(LoggingRouter)
	next := makeCounter()
	call(app, "on", "GET", "/hello", Fn(func(args ...any) any { return "200 你好 #" + fmt.Sprint(next()) }))
	call(app, "on", "GET", "/boom", Fn(func(args ...any) any { panic("坏了") }))
	call(app, "handle", "GET", "/hello")
	call(app, "handle", "GET", "/hello")
	call(app, "handle", "GET", "/boom")
	call(app, "handle", "GET", "/nope")
}
