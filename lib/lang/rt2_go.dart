/// 规矩版本 2 的小库·Go（`lc/lc.go`，包名 lc）。规矩见 docs/blocks-v5-parts/B-type-system.md 第 2、5、7、8、11 节。
///
/// 值在 Go 里的样子（生成器照 7.1 的表）：整数＝int64；小数＝float64；文字＝string；是否＝bool；列表〈T〉＝*lc.List[T]；
/// 字典〈V〉＝lc.Dict[V]（就是 map[string]V，遍历按码点从小到大）；可空的整数 / 小数 / 文字 / 是否 / 记录 / 枚举＝*T，其余可空的用 nil；
/// 记录＝struct（按值）；枚举＝有名字的 int64；变体＝接口＋每种情况一个 struct；类＝*struct（能被继承的是接口＋“体”）；
/// “任意”＝any，里面只放：nil、bool、float64（数字一律）、string、*List[any]、Dict[any]、函数、记录 / 枚举 / 变体 / 对象。
library;

const String kRt2GoSource = r'''
// Package lc 是 LopiCode 积木的小库（Go，严格规矩）。由 LopiCode 生成，别手改。
package lc

import (
	"encoding/json"
	"math"
	"os"
	"reflect"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

const Max = 9007199254740991

type Error struct{ Msg string }

func Fail(m string) { panic(Error{m}) }
func FailV[T any](m string) T {
	panic(Error{m})
}

type Ordered interface {
	~int64 | ~float64 | ~string
}
type named interface{ LcName() string }
type object interface{ LcObj() }
type dynamer interface{ LcDyn() any }
type equaler interface{ LcEq(o any) bool }
type jsoner interface{ LcJson() string }
type enumer interface{ LcEnum() }

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
func BoolText(b bool) string {
	if b {
		return "true"
	}
	return "false"
}

// —— 整数、小数 ——
func chk(r int64) int64 {
	if r > Max || r < -Max {
		Fail("整数超出范围")
	}
	return r
}
func IAdd(a, b int64) int64 { return chk(a + b) }
func ISub(a, b int64) int64 { return chk(a - b) }
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
func FPow(a, b float64) float64 { return math.Pow(a, b) }
func ToInt(x float64) int64 {
	t := math.Trunc(x)
	if math.IsNaN(x) || math.IsInf(x, 0) || math.Abs(t) > Max {
		Fail("这个小数变不成整数：" + FmtNum(x))
	}
	return int64(t)
}
func Floor(x float64) int64 { return ToInt(math.Floor(x)) }
func Ceil(x float64) int64  { return ToInt(math.Ceil(x)) }
func Round(x float64) int64 {
	if math.IsNaN(x) || math.IsInf(x, 0) {
		return ToInt(x)
	}
	t := math.Trunc(x)
	if math.Abs(x-t) >= 0.5 {
		if x < 0 {
			t--
		} else {
			t++
		}
	}
	return ToInt(t)
}
func Sqrt(x float64) float64 { return math.Sqrt(x) }
func Now() float64          { return float64(time.Now().UnixMilli()) }
func Steps(a, b, s int64) int64 {
	if s == 0 || (b > a && s < 0) || (b < a && s > 0) {
		return 0
	}
	return (b-a)/s + 1
}
func FSteps(a, b, s float64) int64 {
	if s == 0 {
		return 0
	}
	d := (b - a) / s
	if !(d >= 0) {
		return 0
	}
	n := math.Floor(d+1e-9) + 1
	if n >= Max {
		return Max
	}
	return int64(n)
}

// —— 文字（按码点） ——
func TextLen(s string) int64 { return int64(utf8.RuneCountInString(s)) }
func CmpText(a, b string) int64 { return int64(strings.Compare(a, b)) }
func Cmp[T Ordered](a, b T) int64 {
	if a < b {
		return -1
	}
	if a > b {
		return 1
	}
	return 0
}
func clamp(i int64, n int) int {
	if i < 0 {
		return 0
	}
	if i > int64(n) {
		return n
	}
	return int(i)
}
func Substring(s string, from, to int64) string {
	r := []rune(s)
	a, b := clamp(from, len(r)), clamp(to, len(r))
	if a >= b {
		return ""
	}
	return string(r[a:b])
}
func CharAt(s string, i int64) string {
	r := []rune(s)
	if i < 0 || i >= int64(len(r)) {
		Fail("位置 " + IntText(i) + " 超出了文字的范围（共 " + strconv.Itoa(len(r)) + " 个字）")
	}
	return string(r[i])
}
func CodePoints(s string) *List[int64] {
	out := &List[int64]{}
	for _, c := range s {
		out.Items = append(out.Items, int64(c))
	}
	return out
}
func Split(s, sep string) *List[string]  { return &List[string]{Items: strings.Split(s, sep)} }
func StartsWith(s, p string) bool        { return strings.HasPrefix(s, p) }
func EndsWith(s, p string) bool          { return strings.HasSuffix(s, p) }
func Contains(s, p string) bool          { return strings.Contains(s, p) }
func IndexOf(s, p string) int64 {
	at := strings.Index(s, p)
	if at < 0 {
		return -1
	}
	return TextLen(s[:at])
}
func Replace(s, from, to string) string {
	if from == "" {
		return s
	}
	return strings.ReplaceAll(s, from, to)
}
func Trim(s string) string {
	return strings.TrimFunc(s, func(r rune) bool {
		return r == '\t' || r == '\n' || r == '\v' || r == '\f' || r == '\r' || r == ' ' || r == 0xa0 || r == 0x1680 || (r >= 0x2000 && r <= 0x200a) || r == 0x2028 || r == 0x2029 || r == 0x202f || r == 0x205f || r == 0x3000 || r == 0xfeff
	})
}
func Upper(s string) string { return strings.Map(unicode.ToUpper, s) }
func Lower(s string) string { return strings.Map(unicode.ToLower, s) }
func RepeatText(s string, n int64) string {
	if n <= 0 {
		return ""
	}
	return strings.Repeat(s, int(n))
}
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

// —— 列表、字典 ——
type List[T any] struct{ Items []T }

func ListOf[T any](items ...T) *List[T] { return &List[T]{Items: items} }
func rangeMsg(i int64, n int) string {
	return "位置 " + IntText(i) + " 超出了列表的范围（共 " + strconv.Itoa(n) + " 项）"
}
func (l *List[T]) Len() int64 { return int64(len(l.Items)) }
func (l *List[T]) Push(v T)   { l.Items = append(l.Items, v) }
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
func (l *List[T]) Snap() []T { return append([]T(nil), l.Items...) }
func (l *List[T]) LcDyn() any {
	if l == nil {
		return nil
	}
	if d, ok := any(l).(*List[any]); ok {
		return d
	}
	out := &List[any]{Items: make([]any, len(l.Items))}
	for i, v := range l.Items {
		out.Items[i] = ToDyn(v)
	}
	return out
}
func (l *List[T]) lcList() {}

// Pop：删掉最后一项并交回来；空列表交回空。PopNil 用在“项本身就能是 nil”的类型上。
func Pop[T any](l *List[T]) *T {
	if len(l.Items) == 0 {
		return nil
	}
	v := l.Items[len(l.Items)-1]
	l.Items = l.Items[:len(l.Items)-1]
	return &v
}
func PopNil[T any](l *List[T]) T {
	if p := Pop(l); p != nil {
		return *p
	}
	var z T
	return z
}

type Dict[V any] map[string]V

func (d Dict[V]) LcDyn() any {
	if d == nil {
		return nil
	}
	if x, ok := any(d).(Dict[any]); ok {
		return x
	}
	out := make(Dict[any], len(d))
	for k, v := range d {
		out[k] = ToDyn(v)
	}
	return out
}
func (d Dict[V]) lcDict() {}
func Keys[V any](d Dict[V]) []string {
	ks := make([]string, 0, len(d))
	for k := range d {
		ks = append(ks, k)
	}
	sort.Strings(ks)
	return ks
}
func Get[V any](d Dict[V], k string) *V {
	if v, ok := d[k]; ok {
		return &v
	}
	return nil
}
func GetNil[V any](d Dict[V], k string) V       { return d[k] }
func DictLen[V any](d Dict[V]) int64            { return int64(len(d)) }
func DictHas[V any](d Dict[V], k string) bool   { _, ok := d[k]; return ok }
func DictKeys[V any](d Dict[V]) *List[string]   { return &List[string]{Items: Keys(d)} }
func DictValues[V any](d Dict[V]) *List[V] {
	out := &List[V]{}
	for _, k := range Keys(d) {
		out.Items = append(out.Items, d[k])
	}
	return out
}
func Map[T, U any](xs *List[T], f func(T) U) *List[U] {
	out := &List[U]{Items: make([]U, 0, len(xs.Items))}
	for _, x := range xs.Snap() {
		out.Items = append(out.Items, f(x))
	}
	return out
}
func Filter[T any](xs *List[T], f func(T) bool) *List[T] {
	out := &List[T]{Items: []T{}}
	for _, x := range xs.Snap() {
		if f(x) {
			out.Items = append(out.Items, x)
		}
	}
	return out
}
func Reduce[T, A any](xs *List[T], f func(A, T) A, init A) A {
	acc := init
	for _, x := range xs.Snap() {
		acc = f(acc, x)
	}
	return acc
}
func Find[T any](xs *List[T], f func(T) bool) *T {
	for _, x := range xs.Snap() {
		if f(x) {
			v := x
			return &v
		}
	}
	return nil
}
func FindNil[T any](xs *List[T], f func(T) bool) T {
	if p := Find(xs, f); p != nil {
		return *p
	}
	var z T
	return z
}
func Every[T any](xs *List[T], f func(T) bool) bool {
	for _, x := range xs.Snap() {
		if !f(x) {
			return false
		}
	}
	return true
}
func Any[T any](xs *List[T], f func(T) bool) bool {
	for _, x := range xs.Snap() {
		if f(x) {
			return true
		}
	}
	return false
}
func Each[T any](xs *List[T], f func(T)) {
	for _, x := range xs.Snap() {
		f(x)
	}
}
func Join(xs *List[string], sep string) string { return strings.Join(xs.Items, sep) }
func Reverse[T any](xs *List[T]) *List[T] {
	out := &List[T]{Items: make([]T, len(xs.Items))}
	for i, v := range xs.Items {
		out.Items[len(xs.Items)-1-i] = v
	}
	return out
}
func Concat[T any](a, b *List[T]) *List[T] {
	return &List[T]{Items: append(append(make([]T, 0, len(a.Items)+len(b.Items)), a.Items...), b.Items...)}
}
func Slice[T any](xs *List[T], from, to int64) *List[T] {
	a, b := clamp(from, len(xs.Items)), clamp(to, len(xs.Items))
	if a >= b {
		return &List[T]{Items: []T{}}
	}
	return &List[T]{Items: append([]T(nil), xs.Items[a:b]...)}
}
func ListIndexOf[T any](xs *List[T], v T) int64 {
	for i, x := range xs.Items {
		if Eq(x, v) {
			return int64(i)
		}
	}
	return -1
}
func ListContains[T any](xs *List[T], v T) bool { return ListIndexOf(xs, v) >= 0 }
func Range(a, b int64) *List[int64] {
	out := &List[int64]{Items: []int64{}}
	for i := a; i <= b; i++ {
		out.Items = append(out.Items, i)
	}
	return out
}

// —— 可空 ——
func Box[T any](v T) *T { return &v }
func Must[T any](p *T) T {
	if p == nil {
		Fail("这里的值是空，不能直接用")
	}
	return *p
}
func MustNil[T any](x T) T {
	if IsNil(x) {
		Fail("这里的值是空，不能直接用")
	}
	return x
}
func IsNil(x any) bool {
	if x == nil {
		return true
	}
	switch rv := reflect.ValueOf(x); rv.Kind() {
	case reflect.Ptr, reflect.Func, reflect.Map, reflect.Interface, reflect.Slice:
		return rv.IsNil()
	}
	return false
}
func OptEq[T comparable](a, b *T) bool {
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	return *a == *b
}
func WidenOpt(p *int64) *float64 {
	if p == nil {
		return nil
	}
	v := float64(*p)
	return &v
}

// Up：换成父类 / 接口的类型（空还是空）。
func Up[I any](x any) I {
	if IsNil(x) {
		var z I
		return z
	}
	return x.(I)
}
func Is[T any](x any) bool {
	if IsNil(x) {
		return false
	}
	_, ok := x.(T)
	return ok
}

// —— 任意 ——
func ToDyn(x any) any {
	switch v := x.(type) {
	case nil:
		return nil
	case bool, float64, string:
		return x
	case int64:
		return float64(v)
	case int:
		return float64(v)
	case dynamer:
		return v.LcDyn()
	}
	rv := reflect.ValueOf(x)
	switch rv.Kind() {
	case reflect.Func, reflect.Map, reflect.Interface, reflect.Slice:
		if rv.IsNil() {
			return nil
		}
	case reflect.Ptr:
		if rv.IsNil() {
			return nil
		}
		if _, ok := x.(object); ok {
			return x
		}
		return ToDyn(rv.Elem().Interface())
	}
	return x
}
func IntDyn(n int64) any { return float64(n) }
func Kind(x any) string {
	x = ToDyn(x)
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
	case Dict[any]:
		return "字典"
	case named:
		return "「" + x.(named).LcName() + "」"
	}
	if reflect.ValueOf(x).Kind() == reflect.Func {
		return "函数"
	}
	return "「对象」"
}
func want[T any](name string, x any) T { return FailV[T]("这里要" + name + "，拿到的是" + Kind(x)) }
func AsNum(x any) float64 {
	if v, ok := x.(float64); ok {
		return v
	}
	return want[float64]("小数", x)
}
func AsInt(x any) int64 {
	v, ok := x.(float64)
	if !ok {
		return want[int64]("整数", x)
	}
	if v != math.Floor(v) || math.Abs(v) > Max {
		Fail("这里要整数，拿到的是 " + FmtNum(v))
	}
	return int64(v)
}
func AsText(x any) string {
	if v, ok := x.(string); ok {
		return v
	}
	return want[string]("文字", x)
}
func AsBool(x any) bool {
	if v, ok := x.(bool); ok {
		return v
	}
	return want[bool]("是否", x)
}
func AsList(x any) *List[any] {
	if v, ok := x.(*List[any]); ok {
		return v
	}
	return want[*List[any]]("列表", x)
}
func AsDict(x any) Dict[any] {
	if v, ok := x.(Dict[any]); ok {
		return v
	}
	return want[Dict[any]]("字典", x)
}
func As[T any](x any, name string) T {
	if v, ok := x.(T); ok && !IsNil(x) {
		return v
	}
	return want[T](name, x)
}
func OptFrom[T any](x any, f func(any) T) *T {
	if x == nil {
		return nil
	}
	v := f(x)
	return &v
}
func NilOr[T any](x any, f func(any) T) T {
	if x == nil {
		var z T
		return z
	}
	return f(x)
}
func ListFrom[T any](x any, f func(any) T) *List[T] {
	src := AsList(x)
	out := &List[T]{Items: make([]T, len(src.Items))}
	for i, v := range src.Items {
		if e, ok := Try(func() { out.Items[i] = f(v) }); !ok {
			Fail("列表的位置 " + strconv.Itoa(i) + "：" + e)
		}
	}
	return out
}
func DictFrom[V any](x any, f func(any) V) Dict[V] {
	src := AsDict(x)
	out := make(Dict[V], len(src))
	for _, k := range Keys(src) {
		if e, ok := Try(func() { out[k] = f(src[k]) }); !ok {
			Fail("字典的「" + k + "」：" + e)
		}
	}
	return out
}

// Eq：两个值按内容相不相等（记录、变体按字段；对象看是不是同一个）。
func Eq(a, b any) bool {
	a, b = ToDyn(a), ToDyn(b)
	if a == nil || b == nil {
		return a == nil && b == nil
	}
	switch x := a.(type) {
	case *List[any]:
		y, ok := b.(*List[any])
		if !ok || len(x.Items) != len(y.Items) {
			return false
		}
		for i := range x.Items {
			if !Eq(x.Items[i], y.Items[i]) {
				return false
			}
		}
		return true
	case Dict[any]:
		y, ok := b.(Dict[any])
		if !ok || len(x) != len(y) {
			return false
		}
		for k, v := range x {
			if w, has := y[k]; !has || !Eq(v, w) {
				return false
			}
		}
		return true
	case equaler:
		return x.LcEq(b)
	}
	ta, tb := reflect.TypeOf(a), reflect.TypeOf(b)
	return ta == tb && ta.Comparable() && a == b
}
func dnum(op string, x any) float64 {
	if v, ok := x.(float64); ok {
		return v
	}
	return FailV[float64](op + "的两边要数字，拿到的是" + Kind(x))
}
func DAdd(a, b any) any { return dnum("加法", a) + dnum("加法", b) }
func DSub(a, b any) any { return dnum("减法", a) - dnum("减法", b) }
func DMul(a, b any) any { return dnum("乘法", a) * dnum("乘法", b) }
func DDiv(a, b any) any { return FDiv(dnum("除法", a), dnum("除法", b)) }
func DPow(a, b any) any { return FPow(dnum("乘方", a), dnum("乘方", b)) }
func DIDiv(a, b any) any { return float64(IDiv(AsInt(a), AsInt(b))) }
func DMod(a, b any) any  { return float64(IMod(AsInt(a), AsInt(b))) }
func DCmp(a, b any) int64 {
	if x, ok := a.(float64); ok {
		if y, ok := b.(float64); ok {
			return Cmp(x, y)
		}
	}
	if x, ok := a.(string); ok {
		if y, ok := b.(string); ok {
			return Cmp(x, y)
		}
	}
	return FailV[int64]("比大小的两边要都是数字或者都是文字，拿到的是" + Kind(a) + "和" + Kind(b))
}
func DynGet(x, k any) any {
	switch v := x.(type) {
	case *List[any]:
		return v.At(AsInt(k))
	case Dict[any]:
		return v[AsText(k)]
	}
	return FailV[any]("这里要列表或字典，拿到的是" + Kind(x))
}
func DynSet(x, k, val any) {
	switch v := x.(type) {
	case *List[any]:
		v.Set(AsInt(k), val)
	case Dict[any]:
		v[AsText(k)] = val
	default:
		Fail("这里要列表或字典，拿到的是" + Kind(x))
	}
}
func DynPush(x, v any)       { AsList(x).Push(v) }
func DynPop(x any) any       { return PopNil(AsList(x)) }
func DynRemove(x, k any)     { delete(AsDict(x), AsText(k)) }
func DynOrElse(x, d any) any {
	if x == nil {
		return d
	}
	return x
}
func DynSize(x any) int64 {
	switch v := x.(type) {
	case string:
		return TextLen(v)
	case *List[any]:
		return v.Len()
	case Dict[any]:
		return int64(len(v))
	}
	return FailV[int64]("这里要文字、列表或字典，拿到的是" + Kind(x))
}

// DynCall：调一个“任意”里的函数（参数、结果都当任意）。
func DynCall(f any, args ...any) any {
	rv := reflect.ValueOf(f)
	if f == nil || rv.Kind() != reflect.Func {
		return want[any]("函数", f)
	}
	ft := rv.Type()
	if ft.NumIn() != len(args) {
		Fail("这个函数要 " + strconv.Itoa(ft.NumIn()) + " 个参数，给了 " + strconv.Itoa(len(args)) + " 个")
	}
	in := make([]reflect.Value, len(args))
	for i, a := range args {
		pt := ft.In(i)
		switch {
		case pt.Kind() == reflect.Int64 && a != nil:
			in[i] = reflect.ValueOf(AsInt(a)).Convert(pt)
		case a == nil:
			in[i] = reflect.Zero(pt)
		case reflect.TypeOf(a).AssignableTo(pt):
			in[i] = reflect.ValueOf(a)
		default:
			Fail("这个函数的第 " + strconv.Itoa(i+1) + " 个参数类型对不上，拿到的是" + Kind(a))
		}
	}
	out := rv.Call(in)
	if len(out) == 0 {
		return nil
	}
	return ToDyn(out[0].Interface())
}
func jstr(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range strings.ToValidUTF8(s, "\ufffd") {
		switch r {
		case '"':
			b.WriteString(`\"`)
		case '\\':
			b.WriteString(`\\`)
		case '\b':
			b.WriteString(`\b`)
		case '\f':
			b.WriteString(`\f`)
		case '\n':
			b.WriteString(`\n`)
		case '\r':
			b.WriteString(`\r`)
		case '\t':
			b.WriteString(`\t`)
		default:
			if r < 0x20 {
				b.WriteString(`\u00`)
				b.WriteByte("0123456789abcdef"[r>>4])
				b.WriteByte("0123456789abcdef"[r&15])
			} else {
				b.WriteRune(r)
			}
		}
	}
	b.WriteByte('"')
	return b.String()
}
func JStr(s string) string { return jstr(s) }
func ToJson(x any) string {
	x = ToDyn(x)
	switch v := x.(type) {
	case nil:
		return "null"
	case bool:
		return BoolText(v)
	case float64:
		if math.IsNaN(v) || math.IsInf(v, 0) {
			return "null"
		}
		return FmtNum(v)
	case string:
		return jstr(v)
	case *List[any]:
		parts := make([]string, len(v.Items))
		for i, it := range v.Items {
			parts[i] = ToJson(it)
		}
		return "[" + strings.Join(parts, ",") + "]"
	case Dict[any]:
		ks := Keys(v)
		parts := make([]string, len(ks))
		for i, k := range ks {
			parts[i] = jstr(k) + ":" + ToJson(v[k])
		}
		return "{" + strings.Join(parts, ",") + "}"
	case jsoner:
		return v.LcJson()
	case enumer:
		return jstr(x.(named).LcName())
	}
	return "null"
}
func fromDecoded(v any) any {
	switch x := v.(type) {
	case []any:
		out := &List[any]{Items: make([]any, len(x))}
		for i, it := range x {
			out.Items[i] = fromDecoded(it)
		}
		return out
	case map[string]any:
		out := make(Dict[any], len(x))
		for k, it := range x {
			out[k] = fromDecoded(it)
		}
		return out
	}
	return v
}
func FromJson(s string) any {
	var v any
	if err := json.Unmarshal([]byte(s), &v); err != nil {
		Fail("这段文字不是 JSON")
	}
	return fromDecoded(v)
}
func DText(x any) string {
	x = ToDyn(x)
	switch v := x.(type) {
	case nil:
		return ""
	case bool:
		return BoolText(v)
	case float64:
		return FmtNum(v)
	case string:
		return v
	case *List[any], Dict[any], jsoner:
		return ToJson(x)
	case enumer:
		return x.(named).LcName()
	case named:
		return "[" + v.LcName() + "]"
	}
	if reflect.ValueOf(x).Kind() == reflect.Func {
		return "[函数]"
	}
	return "[对象]"
}

// —— 出错、输出 ——
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
	os.Stdout.WriteString(strings.Join(out, "\n") + "\n")
}
''';
