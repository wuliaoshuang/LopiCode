/// Go 运行时小库的源码（上半：值的规矩、运算、数据集合；生成的工程里的 `lc/values.go`）。每份工程都一样。
///
/// 只用标准库。值的规矩见 backend_ir.dart 的 `kBeRuntimeFns`，改这里的行为要同时改别的语言的小库
/// （`test/backend_conformance_test.dart` 会让各语言跑同一套请求、比对响应是否逐字节相同）。
/// 源码已经是 gofmt 的规范格式（缩进用制表符），改了以后要重新过一遍 gofmt。
library;

const String kGoRuntimeValuesSource = r'''
// LopiCode 后端运行时小库（Go，只用标准库，不用装任何包）。
// 每份生成的工程都一样，不用改；你的接口在 main.go 里。
//
// 这个文件：值的规矩（空 / 是否 / 数字 / 文字 / 列表 / 对象）、运算、数据集合。
package lc

import (
	"fmt"
	"math"
	"os"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

const (
	bodyLimit      = 1048576 // 请求内容最多 1MB
	repeatLimit    = 10000   // “重复”最多做这么多遍
	jsonDepthLimit = 64      // 请求内容的 JSON 最多套这么多层
)

// fetchTimeout 是“请求别的网址”最多等的时间：10 秒。
const fetchTimeout = 10 * time.Second

// —— 值：nil / bool / float64 / string / []any / map[string]any ——

func kind(v any) string {
	switch v.(type) {
	case nil:
		return "null"
	case bool:
		return "bool"
	case float64:
		return "num"
	case string:
		return "text"
	case []any:
		return "list"
	case map[string]any:
		return "obj"
	}
	return "null"
}

func fin(n float64) float64 {
	if math.IsNaN(n) || math.IsInf(n, 0) {
		return 0
	}
	return n
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }

// isDecimal 判断是不是十进制数的写法：-1.5、.5、1e3（0x10、Infinity 这些不算）。
func isDecimal(s string) bool {
	i, n := 0, len(s)
	if i < n && (s[i] == '+' || s[i] == '-') {
		i++
	}
	whole := 0
	for i < n && isDigit(s[i]) {
		i++
		whole++
	}
	frac := 0
	if i < n && s[i] == '.' {
		i++
		for i < n && isDigit(s[i]) {
			i++
			frac++
		}
		if whole == 0 && frac == 0 {
			return false
		}
	} else if whole == 0 {
		return false
	}
	if i < n && (s[i] == 'e' || s[i] == 'E') {
		i++
		if i < n && (s[i] == '+' || s[i] == '-') {
			i++
		}
		exp := 0
		for i < n && isDigit(s[i]) {
			i++
			exp++
		}
		if exp == 0 {
			return false
		}
	}
	return i == n
}

// toNum 转成数字：转不了的当 0。
func toNum(v any) float64 {
	switch x := v.(type) {
	case float64:
		return fin(x)
	case string:
		s := strings.Trim(x, " \t\r\n")
		if !isDecimal(s) {
			return 0
		}
		n, _ := strconv.ParseFloat(s, 64) // 超出范围时是无穷大，下面当 0
		return fin(n)
	case bool:
		if x {
			return 1
		}
	}
	return 0
}

// fmtNum 是数字的写法：整数不带小数点；其余保留 12 位有效数字（0.1 + 0.2 写成 0.3）。
func fmtNum(v float64) string {
	if math.IsNaN(v) || math.IsInf(v, 0) || v == 0 {
		return "0"
	}
	if v == math.Floor(v) && math.Abs(v) < 1e15 {
		return strconv.FormatFloat(v, 'f', 0, 64)
	}
	minus := ""
	if v < 0 {
		minus = "-"
	}
	// 800 位足够写出任何 float64 的精确十进制值，所以下面自己做的“四舍五入”不会被二次舍入带偏。
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

const hexDigits = "0123456789abcdef"

func quote(b *strings.Builder, s string) {
	b.WriteByte('"')
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c == '"':
			b.WriteString(`\"`)
		case c == '\\':
			b.WriteString(`\\`)
		case c == '\n':
			b.WriteString(`\n`)
		case c == '\r':
			b.WriteString(`\r`)
		case c == '\t':
			b.WriteString(`\t`)
		case c == '\b':
			b.WriteString(`\b`)
		case c == '\f':
			b.WriteString(`\f`)
		case c < 0x20:
			b.WriteString(`\u00`)
			b.WriteByte(hexDigits[c>>4])
			b.WriteByte(hexDigits[c&15])
		default:
			b.WriteByte(c)
		}
	}
	b.WriteByte('"')
}

func writeJSON(b *strings.Builder, v any) {
	switch x := v.(type) {
	case bool:
		if x {
			b.WriteString("true")
		} else {
			b.WriteString("false")
		}
	case float64:
		b.WriteString(fmtNum(x))
	case string:
		quote(b, x)
	case []any:
		b.WriteByte('[')
		for i, item := range x {
			if i > 0 {
				b.WriteByte(',')
			}
			writeJSON(b, item)
		}
		b.WriteByte(']')
	case map[string]any:
		keys := make([]string, 0, len(x))
		for k := range x {
			keys = append(keys, k)
		}
		sort.Strings(keys) // UTF-8 按字节比＝按 Unicode 码点比
		b.WriteByte('{')
		for i, k := range keys {
			if i > 0 {
				b.WriteByte(',')
			}
			quote(b, k)
			b.WriteByte(':')
			writeJSON(b, x[k])
		}
		b.WriteByte('}')
	default:
		b.WriteString("null")
	}
}

// toJSON 写成 JSON：对象的键排好序，数字按上面的写法。
func toJSON(v any) string {
	var b strings.Builder
	writeJSON(&b, v)
	return b.String()
}

// toText 转成文字。
func toText(v any) string {
	switch x := v.(type) {
	case nil:
		return ""
	case string:
		return x
	}
	return toJSON(v)
}

// Truthy 算不算“是”：空、否、0、空文字算“否”。
func Truthy(v any) bool {
	switch x := v.(type) {
	case nil:
		return false
	case bool:
		return x
	case float64:
		return x != 0
	case string:
		return x != ""
	}
	return true
}

// Eq 是“等于”：类型一样直接比；不一样就都转成文字再比。
func Eq(a, b any) bool {
	k := kind(a)
	if k != kind(b) {
		return toText(a) == toText(b)
	}
	switch k {
	case "list", "obj":
		return toJSON(a) == toJSON(b)
	case "num":
		return a.(float64) == b.(float64)
	case "bool":
		return a.(bool) == b.(bool)
	case "text":
		return a.(string) == b.(string)
	}
	return true
}

// —— 运算 ——

func Add(a, b any) float64 { return fin(toNum(a) + toNum(b)) }
func Sub(a, b any) float64 { return fin(toNum(a) - toNum(b)) }
func Mul(a, b any) float64 { return fin(toNum(a) * toNum(b)) }

func Div(a, b any) float64 {
	d := toNum(b)
	if d == 0 {
		return 0
	}
	return fin(toNum(a) / d)
}

func Mod(a, b any) float64 {
	d := toNum(b)
	if d == 0 {
		return 0
	}
	return fin(math.Mod(toNum(a), d))
}

func Ne(a, b any) bool    { return !Eq(a, b) }
func Lt(a, b any) bool    { return toNum(a) < toNum(b) }
func Le(a, b any) bool    { return toNum(a) <= toNum(b) }
func Gt(a, b any) bool    { return toNum(a) > toNum(b) }
func Ge(a, b any) bool    { return toNum(a) >= toNum(b) }
func AllOf(a, b any) bool { return Truthy(a) && Truthy(b) }
func AnyOf(a, b any) bool { return Truthy(a) || Truthy(b) }
func IsNot(x any) bool    { return !Truthy(x) }
func IsNull(x any) bool   { return x == nil }

func Join(items ...any) string {
	var b strings.Builder
	for _, item := range items {
		b.WriteString(toText(item))
	}
	return b.String()
}

func Size(x any) float64 {
	switch v := x.(type) {
	case []any:
		return float64(len(v))
	case string:
		return float64(utf8.RuneCountInString(v))
	case map[string]any:
		return float64(len(v))
	}
	return 0
}

// Obj("title", "买菜", "done", false) → {"title": "买菜", "done": false}
func Obj(pairs ...any) map[string]any {
	o := make(map[string]any, len(pairs)/2)
	for i := 0; i+1 < len(pairs); i += 2 {
		if key, ok := pairs[i].(string); ok {
			o[key] = pairs[i+1]
		}
	}
	return o
}

func Field(o any, key string) any {
	if m, ok := o.(map[string]any); ok {
		return m[key]
	}
	return nil
}

func Times(x any) int {
	n := math.Trunc(toNum(x))
	if n < 0 {
		return 0
	}
	if n > repeatLimit {
		return repeatLimit
	}
	return int(n)
}

func Items(x any) []any {
	if list, ok := x.([]any); ok {
		return append([]any(nil), list...)
	}
	return nil
}

func Now() string {
	return time.Now().UTC().Format("2006-01-02T15:04:05Z")
}

var outLock sync.Mutex

// say 往标准输出写一行。
func say(line string) {
	outLock.Lock()
	defer outLock.Unlock()
	fmt.Fprintln(os.Stdout, line)
}

func Log(x any) { say(toText(x)) }

// —— 数据集合（存在内存里，进程重启就没了）——

type table struct {
	next float64
	rows []map[string]any
}

var (
	tables = map[string]*table{}
	dbLock sync.Mutex // 每个请求一个协程，动集合要排队
)

func tableOf(name string) *table {
	t := tables[name]
	if t == nil {
		t = &table{next: 1}
		tables[name] = t
	}
	return t
}

// Collection 声明一个数据集合。
func Collection(name string) {
	dbLock.Lock()
	defer dbLock.Unlock()
	tableOf(name)
}

func indexOf(rows []map[string]any, id any) int {
	want := toNum(id)
	for i, row := range rows {
		if n, ok := row["id"].(float64); ok && n == want {
			return i
		}
	}
	return -1
}

func DbAll(name string) []any {
	dbLock.Lock()
	defer dbLock.Unlock()
	rows := tableOf(name).rows
	out := make([]any, len(rows))
	for i, row := range rows {
		out[i] = row
	}
	return out
}

func DbCount(name string) float64 {
	dbLock.Lock()
	defer dbLock.Unlock()
	return float64(len(tableOf(name).rows))
}

func DbGet(name string, id any) any {
	dbLock.Lock()
	defer dbLock.Unlock()
	rows := tableOf(name).rows
	if i := indexOf(rows, id); i >= 0 {
		return rows[i]
	}
	return nil
}

func DbFind(name string, key string, value any) []any {
	dbLock.Lock()
	defer dbLock.Unlock()
	out := []any{}
	for _, row := range tableOf(name).rows {
		if Eq(row[key], value) {
			out = append(out, row)
		}
	}
	return out
}

func copyFields(target map[string]any, source any) {
	if m, ok := source.(map[string]any); ok {
		for k, v := range m {
			target[k] = v
		}
	}
}

func DbInsert(name string, value any) any {
	dbLock.Lock()
	defer dbLock.Unlock()
	t := tableOf(name)
	row := map[string]any{}
	copyFields(row, value)
	row["id"] = t.next
	t.next++
	t.rows = append(t.rows, row)
	return row
}

// DbUpdate 改的是一份新的记录（之前读出来的那份不会跟着变）。
func DbUpdate(name string, id any, value any) any {
	dbLock.Lock()
	defer dbLock.Unlock()
	t := tableOf(name)
	i := indexOf(t.rows, id)
	if i < 0 {
		return nil
	}
	if _, ok := value.(map[string]any); !ok {
		return t.rows[i]
	}
	row := map[string]any{}
	copyFields(row, t.rows[i])
	copyFields(row, value)
	row["id"] = t.rows[i]["id"]
	t.rows[i] = row
	return row
}

func DbDelete(name string, id any) bool {
	dbLock.Lock()
	defer dbLock.Unlock()
	t := tableOf(name)
	i := indexOf(t.rows, id)
	if i < 0 {
		return false
	}
	t.rows = append(t.rows[:i:i], t.rows[i+1:]...)
	return true
}
''';
