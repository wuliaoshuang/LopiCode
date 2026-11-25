// Package lc 是类型原型用的“小库”（Go 版）。只为验证类型设计，不是产品代码。
package lc

import (
	"cmp"
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
	"unicode/utf8"
)

const Max = 9007199254740991

type Error struct{ Msg string }

func Fail(m string) { panic(Error{m}) }

func FmtNum(v float64) string {
	switch {
	case math.IsNaN(v):
		return "不是数"
	case math.IsInf(v, 1):
		return "无穷大"
	case math.IsInf(v, -1):
		return "-无穷大"
	case v == 0:
		return "0"
	}
	if v == math.Floor(v) && math.Abs(v) <= Max {
		return strconv.FormatFloat(v, 'f', 0, 64)
	}
	minus := ""
	if v < 0 {
		minus = "-"
	}
	exact := strconv.FormatFloat(math.Abs(v), 'e', 800, 64)
	mark := strings.IndexByte(exact, 'e')
	e, _ := strconv.Atoi(exact[mark+1:])
	all := exact[:1] + exact[2:mark]
	d := []byte(all[:12])
	if all[12] >= '5' {
		i := 11
		for i >= 0 && d[i] == '9' {
			d[i] = '0'
			i--
		}
		if i >= 0 {
			d[i]++
		} else {
			d = append([]byte{'1'}, d[:11]...)
			e++
		}
	}
	digits := strings.TrimRight(string(d), "0")
	switch {
	case e >= 15 || e < -7:
		if len(digits) > 1 {
			return minus + digits[:1] + "." + digits[1:] + "e" + strconv.Itoa(e)
		}
		return minus + digits + "e" + strconv.Itoa(e)
	case e >= len(digits)-1:
		return minus + digits + strings.Repeat("0", e-len(digits)+1)
	case e >= 0:
		return minus + digits[:e+1] + "." + digits[e+1:]
	}
	return minus + "0." + strings.Repeat("0", -e-1) + digits
}

func IntText(n int64) string { return strconv.FormatInt(n, 10) }

func chk(r int64) int64 {
	if r > Max || r < -Max {
		Fail("整数超出范围")
	}
	return r
}

// 两个加数都在 ±(2^53-1) 里，和不会超出 int64，所以先加再查就行。
func IAdd(a, b int64) int64 { return chk(a + b) }
func ISub(a, b int64) int64 { return chk(a - b) }

// 乘法会超出 int64：先用小数估一下大小（差得远就直接报错），再做整数乘法。
func IMul(a, b int64) int64 {
	if math.Abs(float64(a)*float64(b)) > 2*Max {
		Fail("整数超出范围")
	}
	return chk(a * b)
}
func IDiv(a, b int64) int64 {
	if b == 0 {
		Fail("除以 0")
	}
	return a / b
}
func IMod(a, b int64) int64 {
	if b == 0 {
		Fail("除以 0")
	}
	return a % b
}
func FDiv(a, b float64) float64 {
	if b == 0 {
		Fail("除以 0")
	}
	return a / b
}
func FToI(x float64) int64 {
	t := math.Trunc(x)
	if math.IsNaN(x) || math.IsInf(x, 0) || math.Abs(t) > Max {
		Fail("这个小数变不成整数：" + FmtNum(x))
	}
	return int64(t)
}

func TextLen(s string) int64 { return int64(utf8.RuneCountInString(s)) }

func Cmp[T cmp.Ordered](a, b T) int64 { return int64(cmp.Compare(a, b)) }

// List 是列表：一个指针，“在末尾加一项”改的是同一个列表（和别的语言一样）。
type List[T any] struct{ Items []T }

func ListOf[T any](items ...T) *List[T] { return &List[T]{Items: items} }
func (l *List[T]) Len() int64           { return int64(len(l.Items)) }
func (l *List[T]) Push(v T)             { l.Items = append(l.Items, v) }
func rangeMsg(i int64, n int) string {
	return "位置 " + IntText(i) + " 超出了列表的范围（共 " + strconv.Itoa(n) + " 项）"
}
func (l *List[T]) At(i int64) T {
	if i < 0 || i >= int64(len(l.Items)) {
		Fail(rangeMsg(i, len(l.Items)))
	}
	return l.Items[i]
}
func (l *List[T]) Set(i int64, v T) {
	if i < 0 || i >= int64(len(l.Items)) {
		Fail(rangeMsg(i, len(l.Items)))
	}
	l.Items[i] = v
}

func Map[T, U any](xs *List[T], f func(T) U) *List[U] {
	out := &List[U]{Items: make([]U, 0, len(xs.Items))}
	for _, x := range xs.Items {
		out.Items = append(out.Items, f(x))
	}
	return out
}
func Filter[T any](xs *List[T], f func(T) bool) *List[T] {
	out := &List[T]{}
	for _, x := range xs.Items {
		if f(x) {
			out.Items = append(out.Items, x)
		}
	}
	return out
}
func Reduce[T, A any](xs *List[T], init A, f func(A, T) A) A {
	acc := init
	for _, x := range xs.Items {
		acc = f(acc, x)
	}
	return acc
}

// Keys：字典的键，按码点从小到大（Go 的文字按字节比，UTF-8 下和按码点比一样）。
func Keys[V any](d map[string]V) []string {
	ks := make([]string, 0, len(d))
	for k := range d {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}

// Get：字典里取值；没有就是空（nil 指针）。
func Get[V any](d map[string]V, k string) *V {
	if v, ok := d[k]; ok {
		return &v
	}
	return nil
}
func Some[T any](v T) *T { return &v }
func Must[T any](p *T) T {
	if p == nil {
		Fail("这里的值是空，不能直接用")
	}
	return *p
}
func Or[T any](p *T, def T) T {
	if p == nil {
		return def
	}
	return *p
}

// —— 任意 ——
func Kind(x any) string {
	switch x.(type) {
	case nil:
		return "空"
	case bool:
		return "是否"
	case float64:
		return "数字"
	case string:
		return "文字"
	case *List[any]:
		return "列表"
	case map[string]any:
		return "字典"
	}
	return "对象"
}
func want(name string, x any) { Fail("这里要" + name + "，拿到的是" + Kind(x)) }
func AsNum(x any) float64 {
	v, ok := x.(float64)
	if !ok {
		want("小数", x)
	}
	return v
}
func AsInt(x any) int64 {
	v, ok := x.(float64)
	if !ok {
		want("整数", x)
	}
	if v != math.Floor(v) || math.Abs(v) > Max {
		Fail("这里要整数，拿到的是 " + FmtNum(v))
	}
	return int64(v)
}
func AsText(x any) string {
	v, ok := x.(string)
	if !ok {
		want("文字", x)
	}
	return v
}
func AsBool(x any) bool {
	v, ok := x.(bool)
	if !ok {
		want("是否", x)
	}
	return v
}
func AsList(x any) *List[any] {
	v, ok := x.(*List[any])
	if !ok {
		want("列表", x)
	}
	return v
}
func AsDict(x any) map[string]any {
	v, ok := x.(map[string]any)
	if !ok {
		want("字典", x)
	}
	return v
}
func dnum(op string, x any) float64 {
	v, ok := x.(float64)
	if !ok {
		Fail(op + "的两边要数字，拿到的是" + Kind(x))
	}
	return v
}
func DAdd(a, b any) any { return dnum("加法", a) + dnum("加法", b) }
func DSub(a, b any) any { return dnum("减法", a) - dnum("减法", b) }
func DMul(a, b any) any { return dnum("乘法", a) * dnum("乘法", b) }
func DDiv(a, b any) any { return FDiv(dnum("除法", a), dnum("除法", b)) }
func DIDiv(a, b any) any { return float64(IDiv(AsInt(a), AsInt(b))) }
func DIMod(a, b any) any { return float64(IMod(AsInt(a), AsInt(b))) }
func DJson(x any) string {
	switch v := x.(type) {
	case nil:
		return "null"
	case string:
		return `"` + v + `"`
	}
	return DText(x)
}
func DText(x any) string {
	switch v := x.(type) {
	case nil:
		return ""
	case bool:
		return BoolText(v)
	case float64:
		return FmtNum(v)
	case string:
		return v
	case *List[any]:
		parts := make([]string, len(v.Items))
		for i, it := range v.Items {
			parts[i] = DJson(it)
		}
		return "[" + strings.Join(parts, ",") + "]"
	case map[string]any:
		ks := Keys(v)
		parts := make([]string, len(ks))
		for i, k := range ks {
			parts[i] = `"` + k + `":` + DJson(v[k])
		}
		return "{" + strings.Join(parts, ",") + "}"
	}
	return "[" + Kind(x) + "]"
}
func BoolText(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

var out []string

func Log(s string) { out = append(out, s) }

// Try：跑 f；f 里抛了错就把错误文字交回来（ok 是 false）。
func Try(f func()) (msg string, ok bool) {
	defer func() {
		if r := recover(); r != nil {
			e, is := r.(Error)
			if !is {
				panic(r)
			}
			msg, ok = e.Msg, false
		}
	}()
	f()
	return "", true
}
func Run(main func()) {
	if msg, ok := Try(main); !ok {
		out = append(out, "出错："+msg)
	}
	fmt.Fprint(os.Stdout, strings.Join(out, "\n")+"\n")
}

func Join(xs *List[string], sep string) string { return strings.Join(xs.Items, sep) }

func (l *List[T]) Pop() { l.Items = l.Items[:len(l.Items)-1] }
func Split(s, sep string) *List[string] { return &List[string]{Items: strings.Split(s, sep)} }
func Substr(s string, from, to int64) string {
	r := []rune(s)
	return string(r[from:to])
}

// ParseInt：整篇都是十进制整数（可以带负号）而且在整数范围里才算；否则是空。
func ParseInt(s string) *int64 {
	t := strings.TrimPrefix(s, "-")
	if t == "" || strings.Trim(t, "0123456789") != "" {
		return nil
	}
	n, err := strconv.ParseInt(s, 10, 64)
	if err != nil || n > Max || n < -Max {
		return nil
	}
	return &n
}

// 确定类型的列表 / 字典装进“任意”：拍一份快照（第二轮定的规矩）。f 把一项变成“任意里的样子”。
func DynList[T any](xs *List[T], f func(T) any) *List[any] {
	out := &List[any]{Items: make([]any, len(xs.Items))}
	for i, v := range xs.Items {
		out.Items[i] = f(v)
	}
	return out
}
func DynDict[V any](d map[string]V, f func(V) any) map[string]any {
	out := make(map[string]any, len(d))
	for k, v := range d {
		out[k] = f(v)
	}
	return out
}
func IntDyn(n int64) any     { return float64(n) }
func FloatDyn(x float64) any { return x }

// “任意”取回成 列表〈T〉：逐项检查，得到一份新的。
func ListFrom[T any](x any, f func(any) T) *List[T] {
	src := AsList(x)
	out := &List[T]{Items: make([]T, len(src.Items))}
	for i, v := range src.Items {
		if e, ok := Try(func() { out.Items[i] = f(v) }); !ok {
			Fail("列表的位置 " + IntText(int64(i)) + "：" + e)
		}
	}
	return out
}
