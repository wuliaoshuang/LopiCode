/// 规矩版本 2 的小库·Go·下半（“任意”、JSON、出错、输出）。上半在 rt2_go.dart。
library;

import 'package:lopicode/lang/rt2_go.dart';

/// 整份小库。
const String kRt2GoSource = kRt2GoHead + _tail;

const String _tail = r'''
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

// TryE：和 Try 一样，交回来的是整个错（带着错误对象）。
func TryE(f func()) (e Error, ok bool) {
	defer func() {
		if r := recover(); r != nil {
			got, is := r.(Error)
			if !is {
				panic(r)
			}
			e, ok = got, false
		}
	}()
	f()
	return Error{}, true
}
func Run(main func()) {
	msg, ok := Try(main)
	if !ok {
		out = append(out, "出错："+msg)
	}
	os.Stdout.WriteString(strings.Join(out, "\n") + "\n")
	if !ok {
		os.Exit(1)
	}
}
''';
