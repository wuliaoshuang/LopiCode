/// 规矩版本 2 的小库·Go·宿主那一半（`lc/host.go`，和 lc.go 同一个包）：输出、格子、要等的事、开服务。
/// 细则见 docs/blocks-v5-parts/C-library-system.md 9.1 和 B-gen-notes.md 第 12 节。只用 Go 自带的包。
library;

const String kRt2GoHost = r'''
// LopiCode 积木的小库（Go，严格规矩）·宿主那一半。由 LopiCode 生成，别手改。
package lc

import (
	"bytes"
	"io"
	"net"
	"net/http"
	"os"
	"runtime"
	"runtime/debug"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

// —— 输出：写一行就马上写出去（服务被关掉的时候不会丢）；几条线同时写，一行也不会被拆开 ——
var outLock sync.Mutex
var wrote bool

func Log(s string) {
	outLock.Lock()
	defer outLock.Unlock()
	wrote = true
	os.Stdout.WriteString(s + "\n")
}

func errLine(s string) {
	outLock.Lock()
	defer outLock.Unlock()
	os.Stderr.WriteString(s + "\n")
}

func HostPrint(s string, ch string) {
	switch ch {
	case "out":
		Log(s)
	case "err":
		errLine(s)
	default:
		Fail("通道只能是 out 或 err")
	}
}

func HostNow() int64 { return time.Now().UnixMilli() }

func HostEnv(name string) *string {
	v, ok := os.LookupEnv(name)
	if !ok {
		return nil
	}
	return &v
}

func Run(main func()) {
	msg, ok := Try(main)
	if !ok {
		Log("出错：" + msg)
	}
	if !wrote { // 什么都没写过的，补一个空行（和原来“攒到最后一次写”的样子一样）
		os.Stdout.WriteString("\n")
	}
	if !ok {
		os.Exit(1)
	}
}

// —— 格子：每个名字一把锁。别的线同时改同一个名字＝排队；改它的函数里再改它＝报错（不然会自己等自己）——
type storeCell struct {
	lock  sync.Mutex
	owner int64 // 正在改它的那条线的编号；没人在改是 0
}

var storeLock sync.Mutex
var store = map[string]any{}
var storeCells = map[string]*storeCell{}

// 这条线的编号。Go 不给现成的，从“我在哪”那段文字的开头（goroutine 12 [running]:）里读。
func lineID() int64 {
	buf := make([]byte, 64)
	buf = buf[:runtime.Stack(buf, false)]
	buf = bytes.TrimPrefix(buf, []byte("goroutine "))
	if i := bytes.IndexByte(buf, ' '); i > 0 {
		if id, err := strconv.ParseInt(string(buf[:i]), 10, 64); err == nil {
			return id
		}
	}
	return -1
}

func copyVal(v any) any {
	switch x := v.(type) {
	case *List[any]:
		c := &List[any]{}
		for _, it := range x.Items {
			c.Items = append(c.Items, copyVal(it))
		}
		return c
	case Dict[any]:
		c := Dict[any]{}
		for k, it := range x {
			c[k] = copyVal(it)
		}
		return c
	}
	return v
}

func StoreRead(name string) any {
	storeLock.Lock()
	defer storeLock.Unlock()
	return copyVal(store[name])
}

func StoreUpdate(name string, f func(any) any) any {
	me := lineID()
	storeLock.Lock()
	cell := storeCells[name]
	if cell == nil {
		cell = &storeCell{}
		storeCells[name] = cell
	}
	busy := cell.owner == me
	storeLock.Unlock()
	if busy {
		Fail("「" + name + "」这个格子正在改，不能在改它的函数里再改它")
	}
	cell.lock.Lock()
	storeLock.Lock()
	cell.owner = me
	storeLock.Unlock()
	defer func() {
		storeLock.Lock()
		cell.owner = 0
		storeLock.Unlock()
		cell.lock.Unlock()
	}()
	v := copyVal(f(StoreRead(name)))
	storeLock.Lock()
	store[name] = v
	storeLock.Unlock()
	return copyVal(v)
}

// —— 要等的事：一件事一条线 ——
func HostSleep(ms int64) {
	if ms > 0 {
		time.Sleep(time.Duration(ms) * time.Millisecond)
	}
}

// Task：“开始做”的结果。做完了 done 会关上；出了错先记着，等它的时候再抛。
type Task[T any] struct {
	done chan struct{}
	val  T
	err  any
}

func Spawn[T any](f func() T) *Task[T] {
	t := &Task[T]{done: make(chan struct{})}
	go func() {
		defer close(t.done)
		defer func() { t.err = recover() }()
		t.val = f()
	}()
	return t
}

func Wait[T any](t *Task[T]) T {
	<-t.done
	if t.err != nil {
		panic(t.err)
	}
	return t.val
}

// —— 开服务 ——
const bodyLimit = 1048576

func writeRaw(w http.ResponseWriter, r *http.Request, status int, headers Dict[any], text string) {
	noBody := status == 204 || status == 304 || status < 200
	h := w.Header()
	h["Content-Type"] = nil // 不许 Go 自己猜内容类型
	keys := Keys(headers)
	sort.Strings(keys)
	for _, k := range keys {
		if !strings.EqualFold(k, "content-length") {
			h[http.CanonicalHeaderKey(k)] = []string{DText(headers[k])}
		}
	}
	if !noBody {
		h["Content-Length"] = []string{strconv.Itoa(len(text))}
	}
	w.WriteHeader(status)
	if !noBody && r.Method != "HEAD" {
		io.WriteString(w, text)
	}
}

func hostError(w http.ResponseWriter, r *http.Request, status int, message string) {
	writeRaw(w, r, status, Dict[any]{"Content-Type": "application/json; charset=utf-8"}, ToJson(Dict[any]{"error": message}))
}

func serveOne(w http.ResponseWriter, r *http.Request, handler func(Dict[any]) Dict[any]) {
	if r.ContentLength > bodyLimit {
		w.Header()["Connection"] = []string{"close"}
		hostError(w, r, 413, "请求内容太大")
		return
	}
	raw, _ := io.ReadAll(io.LimitReader(r.Body, bodyLimit+1))
	if len(raw) > bodyLimit {
		w.Header()["Connection"] = []string{"close"}
		hostError(w, r, 413, "请求内容太大")
		return
	}
	var body any
	if utf8.Valid(raw) {
		body = string(raw)
	}
	headers := Dict[any]{}
	if r.Host != "" {
		headers["host"] = r.Host
	}
	for name, values := range r.Header {
		for i, v := range values {
			values[i] = strings.Trim(v, " \t")
		}
		headers[strings.ToLower(name)] = strings.Join(values, ", ")
	}
	path, query, _ := strings.Cut(r.RequestURI, "?")
	request := Dict[any]{"method": r.Method, "path": path, "query": query, "headers": headers, "body": body}
	var out Dict[any]
	failed := func() (bad bool) {
		defer func() {
			if e := recover(); e != nil {
				bad = true
				if le, is := e.(Error); is {
					errLine("出错：" + le.Msg)
				} else {
					errLine(strings.TrimRight(DText(e)+"\n"+string(debug.Stack()), "\n"))
				}
			}
		}()
		out = handler(request)
		return false
	}()
	if failed {
		hostError(w, r, 500, "服务器内部出错")
		return
	}
	status, isNum := out["status"].(float64)
	if !isNum || status != float64(int(status)) || status < 100 || status > 599 {
		errLine("处理函数返回的响应不对（要一个字典，status 是 100 到 599 的整数）")
		hostError(w, r, 500, "服务器内部出错")
		return
	}
	hs, _ := out["headers"].(Dict[any])
	writeRaw(w, r, int(status), hs, DText(out["body"]))
}

// HostServe：一直服务，不返回；端口用不了＝出错。
func HostServe(port int64, host string, handler func(Dict[any]) Dict[any]) {
	if port < 0 || port > 65535 {
		Fail("开不了服务：端口要在 0 到 65535 之间")
	}
	ln, err := net.Listen("tcp", net.JoinHostPort(host, strconv.FormatInt(port, 10)))
	if err != nil {
		Fail("开不了服务：" + host + ":" + strconv.FormatInt(port, 10) + " 用不了")
	}
	Log("后端已启动：http://" + host + ":" + strconv.Itoa(ln.Addr().(*net.TCPAddr).Port))
	server := &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { serveOne(w, r, handler) })}
	server.Serve(ln)
	select {}
}
''';
