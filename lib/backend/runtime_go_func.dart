/// Go 语言核心小库里“函数”那一部分（积木第 4 版·第 2 阶段）：函数值、调用、拿函数当参数的 8 个列表操作。
/// 接在 `kGoLangRuntimeSource` 后面，同一个文件（`lc/lang.go`）；`Fn` 这个类型在 `lc/values.go`（runtime_go.dart）里。
/// 规矩见 lib/lang/rt.dart；五种语言要一起改。
library;

const String kGoLangFuncSource = r'''
// —— 函数（第 2 阶段）——

const (
	errNotFunction = "这不是函数，不能调用"
	errArgCount    = "调用函数时给的参数个数对不上"
)

// NewFn 造一个函数值：名字、最少 / 最多收几个参数（最多是 -1＝不限）、实现（收一个参数表）。
func NewFn(name string, min int, max int, do func(args []any) any) any {
	return &Fn{Name: name, Min: min, Max: max, Do: do}
}

func needFn(f any) *Fn {
	fn, ok := f.(*Fn)
	if !ok || fn == nil || fn.Do == nil {
		panic(errNotFunction)
	}
	return fn
}

// Call 调一个函数值：不是函数、参数个数对不上 → 抛错。没有返回值的函数得空。
func Call(f any, args ...any) any {
	fn := needFn(f)
	if len(args) < fn.Min || (fn.Max >= 0 && len(args) > fn.Max) {
		panic(errArgCount)
	}
	return fn.Do(args)
}

// Arg 取第 i 个参数；没给就是空。
func Arg(args []any, i int) any {
	if i < len(args) {
		return args[i]
	}
	return nil
}

// ArgOr 取第 i 个参数；没给就用默认值。
func ArgOr(args []any, i int, d any) any {
	if i < len(args) {
		return args[i]
	}
	return d
}

// Rest 把第 i 个起剩下的参数收成一个列表。
func Rest(args []any, i int) any {
	if i >= len(args) {
		return NewList([]any{})
	}
	return NewList(append([]any{}, args[i:]...))
}

// langEach：开始时把列表抄一份再走，回调里改了原来的列表也不影响这一趟。
func langEach(xs any, f any) ([]any, *Fn) {
	fn := needFn(f)
	return append([]any{}, langItems(xs)...), fn
}

func ListMap(xs any, f any) any {
	items, _ := langEach(xs, f)
	out := make([]any, 0, len(items))
	for _, x := range items {
		out = append(out, Call(f, x))
	}
	return NewList(out)
}

func ListFilter(xs any, f any) any {
	items, _ := langEach(xs, f)
	out := []any{}
	for _, x := range items {
		if Truthy(Call(f, x)) {
			out = append(out, x)
		}
	}
	return NewList(out)
}

func ListReduce(xs any, f any, init any) any {
	items, _ := langEach(xs, f)
	acc := init
	for _, x := range items {
		acc = Call(f, acc, x)
	}
	return acc
}

func ListFind(xs any, f any) any {
	items, _ := langEach(xs, f)
	for _, x := range items {
		if Truthy(Call(f, x)) {
			return x
		}
	}
	return nil
}

func ListEvery(xs any, f any) bool {
	items, _ := langEach(xs, f)
	for _, x := range items {
		if !Truthy(Call(f, x)) {
			return false
		}
	}
	return true
}

func ListSome(xs any, f any) bool {
	items, _ := langEach(xs, f)
	for _, x := range items {
		if Truthy(Call(f, x)) {
			return true
		}
	}
	return false
}

func ListEach(xs any, f any) {
	items, _ := langEach(xs, f)
	for _, x := range items {
		Call(f, x)
	}
}

// ListSortBy 按 f(项) 给的分从小到大：分是数字的排前面、按大小；其余的文字化后按码点；一样的保持原来的先后。
func ListSortBy(xs any, f any) any {
	items, _ := langEach(xs, f)
	keyed := make([]langSortKey, len(items))
	for i, item := range items {
		k := Call(f, item)
		if n, ok := k.(float64); ok {
			keyed[i] = langSortKey{value: item, isNum: true, num: n}
		} else {
			keyed[i] = langSortKey{value: item, text: toText(k)}
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
''';
