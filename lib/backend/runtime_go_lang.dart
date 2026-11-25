/// Go 的语言核心小库（生成的工程里的 `lc/lang.go`，和 `lc/values.go` 同一个包）：积木第 4 版新加的操作。
/// 只有用到新积木的工程才带这个文件。
///
/// 函数表和规矩见 lib/lang/rt.dart 的 `kLangRtFns`；改这里的行为要同时改别的语言的
/// （`test/lang_conformance_test.dart` 让各语言跑同一批程序、比对输出是否逐字节相同）。
/// 源码已经是 gofmt 的规范格式（缩进用制表符），改了以后要重新过一遍 gofmt。
library;

const String kGoLangRuntimeSource = r'''
// LopiCode 语言核心小库（Go）：积木第 4 版新加的操作——类型、数学、文字、列表、字典、JSON、数列。
// 每份生成的工程都一样，不用改。规矩：位置从 0 数；文字按 Unicode 码点算；读不到得空；写到不存在的位置抛错（panic）。
package lc

import (
	"math"
	"math/rand"
	"regexp"
	"sort"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const (
	rangeLimit = 10000      // “数列”“重复文字”最多这么多项
	countLimit = 2147483647 // “从…数到…”最多数这么多遍
)

const (
	errNotList      = "这不是列表，改不了"
	errNotDict      = "这不是字典，改不了"
	errNoItem       = "列表里没有这个位置"
	errNotIndexable = "这个值不能按位置或键来改"
)

var langHole = regexp.MustCompile(`\{([^{}]*)\}`)

var (
	langRandLock sync.Mutex
	langRand     = rand.New(rand.NewSource(time.Now().UnixNano()))
)

// langPz 去掉“负零”（各语言写出来不一样）。
func langPz(n float64) float64 {
	if n == 0 {
		return 0
	}
	return n
}

// langIndex 把位置数字化、去掉小数部分；大得离谱的夹在 ±2^53 里（转成整数才不会出问题）。
func langIndex(i any) int {
	n := math.Trunc(toNum(i))
	if n > 9007199254740992 {
		return 9007199254740992
	}
	if n < -9007199254740992 {
		return -9007199254740992
	}
	return int(n)
}

func langClamp(n, lo, hi int) int {
	if n < lo {
		return lo
	}
	if n > hi {
		return hi
	}
	return n
}

// langItems 是列表里的那一串值（不复制）；不是列表就是空的。
func langItems(x any) []any {
	if list, ok := x.(*List); ok {
		return list.items
	}
	return nil
}

func langDict(x any) (map[string]any, bool) {
	d, ok := x.(map[string]any)
	return d, ok
}

func langKeys(d map[string]any) []string {
	keys := make([]string, 0, len(d))
	for k := range d {
		keys = append(keys, k)
	}
	sort.Strings(keys) // UTF-8 按字节比＝按 Unicode 码点比
	return keys
}

// Pick 是值版的“如果”：只算选中的那一边。
func Pick(cond bool, then func() any, orElse func() any) any {
	if cond {
		return then()
	}
	return orElse()
}

// —— 类型 ——

var langTypeNames = map[string]string{"num": "number", "text": "text", "bool": "bool", "null": "null", "list": "list", "obj": "dict"}

func IsType(x any, name any) bool { return langTypeNames[kind(x)] == toText(name) }
func ToNumber(x any) float64      { return toNum(x) }
func ToText(x any) string         { return toText(x) }
func ToBool(x any) bool           { return Truthy(x) }

func Copy(x any) any {
	switch v := x.(type) {
	case *List:
		out := make([]any, len(v.items))
		for i, item := range v.items {
			out[i] = Copy(item)
		}
		return NewList(out)
	case map[string]any:
		out := make(map[string]any, len(v))
		for k, item := range v {
			out[k] = Copy(item)
		}
		return out
	}
	return x
}

// —— 数学 ——

func Pow(a any, b any) float64 { return langPz(fin(math.Pow(toNum(a), toNum(b)))) }

func Round(x any) float64 {
	n := toNum(x)
	t := math.Trunc(n)
	if math.Abs(n-t) >= 0.5 {
		if n < 0 {
			return langPz(t - 1)
		}
		return langPz(t + 1)
	}
	return langPz(t)
}

func Floor(x any) float64 { return langPz(math.Floor(toNum(x))) }
func Ceil(x any) float64  { return langPz(math.Ceil(toNum(x))) }
func Abs(x any) float64   { return math.Abs(toNum(x)) }

func Sqrt(x any) float64 {
	n := toNum(x)
	if n < 0 {
		return 0
	}
	return math.Sqrt(n)
}

func Max(a any, b any) float64 {
	x, y := toNum(a), toNum(b)
	if x >= y {
		return x
	}
	return y
}

func Min(a any, b any) float64 {
	x, y := toNum(a), toNum(b)
	if x <= y {
		return x
	}
	return y
}

func Random(a any, b any) float64 {
	lo, hi := math.Trunc(toNum(a)), math.Trunc(toNum(b))
	if lo > hi {
		lo, hi = hi, lo
	}
	langRandLock.Lock()
	r := langRand.Float64()
	langRandLock.Unlock()
	return langPz(lo + math.Floor(r*(hi-lo+1)))
}

// —— 文字 ——

func CharAt(s any, i any) any {
	cs := []rune(toText(s))
	n := langIndex(i)
	if n < 0 || n >= len(cs) {
		return nil
	}
	return string(cs[n])
}

func Substring(s any, from any, to any) string {
	cs := []rune(toText(s))
	a := langClamp(langIndex(from), 0, len(cs))
	b := langClamp(langIndex(to), 0, len(cs))
	if a >= b {
		return ""
	}
	return string(cs[a:b])
}

func Contains(s any, sub any) bool { return strings.Contains(toText(s), toText(sub)) }
func StartsWith(s any, p any) bool { return strings.HasPrefix(toText(s), toText(p)) }
func EndsWith(s any, p any) bool   { return strings.HasSuffix(toText(s), toText(p)) }

func IndexOf(s any, sub any) float64 {
	text := toText(s)
	at := strings.Index(text, toText(sub))
	if at < 0 {
		return -1
	}
	return float64(utf8.RuneCountInString(text[:at]))
}

func Replace(s any, from any, to any) string {
	f := toText(from)
	if f == "" {
		return toText(s)
	}
	return strings.ReplaceAll(toText(s), f, toText(to))
}

func Split(s any, sep any) any {
	text, p := toText(s), toText(sep)
	out := []any{}
	if p == "" {
		for _, r := range text {
			out = append(out, string(r))
		}
		return NewList(out)
	}
	for _, part := range strings.Split(text, p) {
		out = append(out, part)
	}
	return NewList(out)
}

func Trim(s any) string { return strings.Trim(toText(s), " \t\r\n") }

func Upper(s any) string {
	return strings.Map(func(r rune) rune {
		if r >= 'a' && r <= 'z' {
			return r - 32
		}
		return r
	}, toText(s))
}

func Lower(s any) string {
	return strings.Map(func(r rune) rune {
		if r >= 'A' && r <= 'Z' {
			return r + 32
		}
		return r
	}, toText(s))
}

func RepeatText(s any, n any) string {
	return strings.Repeat(toText(s), langClamp(langIndex(n), 0, rangeLimit))
}

func Template(s any, d any) string {
	dict, ok := langDict(d)
	return langHole.ReplaceAllStringFunc(toText(s), func(whole string) string {
		if !ok {
			return whole
		}
		if v, has := dict[whole[1:len(whole)-1]]; has {
			return toText(v)
		}
		return whole
	})
}

// —— 列表 ——

func ListOf(xs ...any) any { return NewList(append([]any{}, xs...)) }

func ListGet(xs any, i any) any {
	items := langItems(xs)
	n := langIndex(i)
	if n < 0 || n >= len(items) {
		return nil
	}
	return items[n]
}

func ListSet(xs any, i any, v any) {
	list, ok := xs.(*List)
	if !ok {
		panic(errNotList)
	}
	n := langIndex(i)
	if n < 0 || n >= len(list.items) {
		panic(errNoItem)
	}
	list.items[n] = v
}

func ListPush(xs any, v any) {
	list, ok := xs.(*List)
	if !ok {
		panic(errNotList)
	}
	list.items = append(list.items, v)
}

func ListInsert(xs any, i any, v any) {
	list, ok := xs.(*List)
	if !ok {
		panic(errNotList)
	}
	n := langIndex(i)
	if n < 0 || n > len(list.items) {
		panic(errNoItem)
	}
	list.items = append(list.items, nil)
	copy(list.items[n+1:], list.items[n:])
	list.items[n] = v
}

func ListRemove(xs any, i any) any {
	list, ok := xs.(*List)
	if !ok {
		panic(errNotList)
	}
	n := langIndex(i)
	if n < 0 || n >= len(list.items) {
		panic(errNoItem)
	}
	gone := list.items[n]
	list.items = append(list.items[:n], list.items[n+1:]...)
	return gone
}

func ListPop(xs any) any {
	list, ok := xs.(*List)
	if !ok || len(list.items) == 0 {
		return nil
	}
	last := list.items[len(list.items)-1]
	list.items = list.items[:len(list.items)-1]
	return last
}

func ListIndexOf(xs any, v any) float64 {
	for i, item := range langItems(xs) {
		if Eq(item, v) {
			return float64(i)
		}
	}
	return -1
}

func ListContains(xs any, v any) bool { return ListIndexOf(xs, v) >= 0 }

func ListSlice(xs any, from any, to any) any {
	items := langItems(xs)
	a := langClamp(langIndex(from), 0, len(items))
	b := langClamp(langIndex(to), 0, len(items))
	if a >= b {
		return NewList([]any{})
	}
	return NewList(append([]any{}, items[a:b]...))
}

func ListConcat(a any, b any) any {
	out := append([]any{}, langItems(a)...)
	return NewList(append(out, langItems(b)...))
}

func ListReverse(xs any) any {
	items := langItems(xs)
	out := make([]any, len(items))
	for i, item := range items {
		out[len(items)-1-i] = item
	}
	return NewList(out)
}

type langSortKey struct {
	value any
	isNum bool
	num   float64
	text  string
}

// ListSort：数字排在前面、按大小；其余的文字化后按码点。
func ListSort(xs any) any {
	items := langItems(xs)
	keyed := make([]langSortKey, len(items))
	for i, item := range items {
		if n, ok := item.(float64); ok {
			keyed[i] = langSortKey{value: item, isNum: true, num: n}
		} else {
			keyed[i] = langSortKey{value: item, text: toText(item)}
		}
	}
	sort.SliceStable(keyed, func(i, j int) bool {
		x, y := keyed[i], keyed[j]
		if x.isNum && y.isNum {
			return x.num < y.num
		}
		if x.isNum != y.isNum {
			return x.isNum
		}
		return x.text < y.text
	})
	out := make([]any, len(keyed))
	for i, k := range keyed {
		out[i] = k.value
	}
	return NewList(out)
}

func ListJoin(xs any, sep any) string {
	items := langItems(xs)
	parts := make([]string, len(items))
	for i, item := range items {
		parts[i] = toText(item)
	}
	return strings.Join(parts, toText(sep))
}

// CountSteps 是“从…数到…”要做几遍。
func CountSteps(from any, to any, step any) int {
	a, s := toNum(from), toNum(step)
	if s == 0 {
		return 0
	}
	d := (toNum(to) - a) / s
	if !(d >= 0) {
		return 0
	}
	if d >= countLimit {
		return countLimit
	}
	n := int(math.Floor(d+1e-9)) + 1
	if n > countLimit {
		return countLimit
	}
	return n
}

func Range(from any, to any, step any) any {
	a, s := toNum(from), toNum(step)
	n := CountSteps(a, to, s)
	if n > rangeLimit {
		n = rangeLimit
	}
	out := make([]any, n)
	for k := 0; k < n; k++ {
		out[k] = a + float64(k)*s
	}
	return NewList(out)
}

// —— 字典 ——

func DictOf(pairs ...any) any {
	out := map[string]any{}
	for i := 0; i+1 < len(pairs); i += 2 {
		out[toText(pairs[i])] = pairs[i+1]
	}
	return out
}

func DictHas(d any, k any) bool {
	dict, ok := langDict(d)
	if !ok {
		return false
	}
	_, has := dict[toText(k)]
	return has
}

func DictGet(d any, k any) any {
	if dict, ok := langDict(d); ok {
		return dict[toText(k)]
	}
	return nil
}

func DictSet(d any, k any, v any) {
	dict, ok := langDict(d)
	if !ok {
		panic(errNotDict)
	}
	dict[toText(k)] = v
}

func DictRemove(d any, k any) {
	dict, ok := langDict(d)
	if !ok {
		panic(errNotDict)
	}
	delete(dict, toText(k))
}

func DictKeys(d any) any {
	dict, _ := langDict(d)
	out := []any{}
	for _, k := range langKeys(dict) {
		out = append(out, k)
	}
	return NewList(out)
}

func DictValues(d any) any {
	dict, _ := langDict(d)
	out := []any{}
	for _, k := range langKeys(dict) {
		out = append(out, dict[k])
	}
	return NewList(out)
}

func DictPairs(d any) any {
	dict, _ := langDict(d)
	out := []any{}
	for _, k := range langKeys(dict) {
		out = append(out, NewList([]any{k, dict[k]}))
	}
	return NewList(out)
}

func DictMerge(a any, b any) any {
	out := map[string]any{}
	for _, d := range []any{a, b} {
		if dict, ok := langDict(d); ok {
			for k, v := range dict {
				out[k] = v
			}
		}
	}
	return out
}

// —— 列表 / 字典 / 文字通用 ——

func Item(x any, k any) any {
	switch x.(type) {
	case *List:
		return ListGet(x, k)
	case map[string]any:
		return DictGet(x, k)
	case string:
		return CharAt(x, k)
	}
	return nil
}

func SetItem(x any, k any, v any) {
	switch x.(type) {
	case *List:
		ListSet(x, k, v)
	case map[string]any:
		DictSet(x, k, v)
	default:
		panic(errNotIndexable)
	}
}

// —— JSON ——

func ToJson(x any) string { return toJSON(x) }
func FromJson(s any) any  { return parseBody([]byte(toText(s))) }
''';
