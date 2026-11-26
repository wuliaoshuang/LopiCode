/// 规矩版本 2 的小库·Go·第三份（`lc/more.go`）：后端积木里早就有、核心 2 的 A5 段补上的那几个函数
/// （绝对值、较大、较小、随机整数、复制、套模板、算不算是、插入 / 删掉一项、排序、一对对、三个参数的数列）。
/// 规矩见 lib/lang/rt_v2.dart 里各自的说明和 docs/blocks-v5-parts/B-gen-notes.md 第 13 节。
library;

const String kRt2GoMore = r'''
package lc

import (
	"math"
	"math/rand"
	"sort"
	"strings"
)

// Num：整数或小数。
type Num interface{ ~int64 | ~float64 }

func Abs[T Num](x T) T {
	if x < 0 {
		return -x
	}
	return x
}
func MaxOf[T Num](a, b T) T {
	if a >= b {
		return a
	}
	return b
}
func MinOf[T Num](a, b T) T {
	if a <= b {
		return a
	}
	return b
}
func numArg(name string, x any) float64 {
	v, ok := ToDyn(x).(float64)
	if !ok {
		Fail("「" + name + "」要数字，拿到的是" + Kind(x))
	}
	return v
}
func DynAbs(x any) any { return math.Abs(numArg("绝对值", x)) }
func DynMax(a, b any) any {
	if numArg("较大的", a) >= numArg("较大的", b) {
		return ToDyn(a)
	}
	return ToDyn(b)
}
func DynMin(a, b any) any {
	if numArg("较小的", a) <= numArg("较小的", b) {
		return ToDyn(a)
	}
	return ToDyn(b)
}
func Random(a, b int64) int64 {
	if a > b {
		a, b = b, a
	}
	return a + rand.Int63n(b-a+1)
}

// —— 复制：列表、字典连里面的一层层都另做一份 ——
type copier interface{ LcCopy() any }

func (l *List[T]) LcCopy() any {
	if l == nil {
		return l
	}
	out := &List[T]{Items: make([]T, len(l.Items))}
	for i, v := range l.Items {
		out.Items[i] = Copy(v)
	}
	return out
}
func (d Dict[V]) LcCopy() any {
	if d == nil {
		return d
	}
	out := Dict[V]{}
	for k, v := range d {
		out[k] = Copy(v)
	}
	return out
}
func Copy[T any](x T) T {
	if c, ok := any(x).(copier); ok {
		return c.LcCopy().(T)
	}
	return x
}

func Template[V any](s string, d Dict[V]) string {
	var out strings.Builder
	i := 0
	for i < len(s) {
		open := strings.IndexByte(s[i:], '{')
		if open < 0 {
			break
		}
		open += i
		end := open + 1
		for end < len(s) && s[end] != '}' && s[end] != '{' {
			end++
		}
		if end >= len(s) || s[end] == '{' {
			out.WriteString(s[i:end])
			i = end
			continue
		}
		out.WriteString(s[i:open])
		if v, ok := d[s[open+1:end]]; ok {
			out.WriteString(DText(v))
		} else {
			out.WriteString(s[open : end+1])
		}
		i = end + 1
	}
	out.WriteString(s[i:])
	return out.String()
}
func ToBool(x any) bool {
	switch v := ToDyn(x).(type) {
	case nil:
		return false
	case bool:
		return v
	case float64:
		return v != 0
	case string:
		return v != ""
	}
	return true
}
func Insert[T any](xs *List[T], i int64, v T) {
	if i < 0 || i > int64(len(xs.Items)) {
		Fail(rangeMsg(i, len(xs.Items)))
	}
	var zero T
	xs.Items = append(xs.Items, zero)
	copy(xs.Items[i+1:], xs.Items[i:])
	xs.Items[i] = v
}
func RemoveAt[T any](xs *List[T], i int64) T {
	if i < 0 || i >= int64(len(xs.Items)) {
		Fail(rangeMsg(i, len(xs.Items)))
	}
	v := xs.Items[i]
	xs.Items = append(xs.Items[:i], xs.Items[i+1:]...)
	return v
}
func Sort[T Ordered](xs *List[T]) *List[T] {
	out := &List[T]{Items: xs.Snap()}
	sort.SliceStable(out.Items, func(i, j int) bool { return out.Items[i] < out.Items[j] })
	return out
}
func DynSort(xs *List[any]) *List[any] {
	nums, texts := true, true
	for _, v := range xs.Items {
		switch ToDyn(v).(type) {
		case float64:
			texts = false
		case string:
			nums = false
		default:
			nums, texts = false, false
		}
	}
	if !nums && !texts {
		Fail("排序要全是数字或者全是文字的列表，拿到的是混着的")
	}
	out := &List[any]{Items: xs.Snap()}
	sort.SliceStable(out.Items, func(i, j int) bool { return DCmp(out.Items[i], out.Items[j]) < 0 })
	return out
}
func DictPairs[V any](d Dict[V]) *List[*List[any]] {
	out := &List[*List[any]]{Items: []*List[any]{}}
	for _, k := range Keys(d) {
		out.Items = append(out.Items, &List[any]{Items: []any{k, ToDyn(d[k])}})
	}
	return out
}
func Range(a, b, s int64) *List[int64] {
	out := &List[int64]{Items: []int64{}}
	n := Steps(a, b, s)
	if n > 10000 {
		n = 10000
	}
	for k := int64(0); k < n; k++ {
		out.Items = append(out.Items, a+k*s)
	}
	return out
}
''';
