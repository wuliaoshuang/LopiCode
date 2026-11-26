/// 规矩版本 2 的小库·Go·宿主那一半（`lc/host.go`，和 lc.go 同一个包）：输出、格子、开服务。要等的事在 rt2_go_task.dart（`lc/task.go`）。
/// 细则见 docs/blocks-v5-parts/C-library-system.md 9.1 和 B-gen-notes.md 第 12 节。只用 Go 自带的包。
library;

const String kRt2GoHost = r'''
// LopiCode 积木的小库（Go，严格规矩）·宿主那一半。由 LopiCode 生成，别手改。
package lc

import (
	"bytes"
	"context"
	"io"
	"net"
	"net/http"
	"os"
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

func Run(main func(*Line)) {
	msg, ok := Try(func() { main(&Line{}) })
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
	owner *Line // 正在改它的那条线；没人在改是 nil
}

var storeLock sync.Mutex
var store = map[string]any{}
var storeCells = map[string]*storeCell{}

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

func StoreUpdate(me *Line, name string, f func(*Line, any) any) any {
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
		cell.owner = nil
		storeLock.Unlock()
		cell.lock.Unlock()
	}()
	v := copyVal(f(me, StoreRead(name)))
	storeLock.Lock()
	store[name] = v
	storeLock.Unlock()
	return copyVal(v)
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

func serveOne(w http.ResponseWriter, r *http.Request, handler func(*Line, Dict[any]) Dict[any]) {
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
	target := r.RequestURI
	if c, ok := r.Context().Value(connKey{}).(*rawConn); ok && c.target != "" {
		target = c.target
	}
	path, query, _ := strings.Cut(target, "?")
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
		out = handler(&Line{}, request) // 一个请求一条线
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

// —— 请求行里写法不对的百分号 ——
// Go 的 net/http 碰到地址里有 %zz 这种写法会直接回 400，到不了处理函数；规矩是“原样交给处理函数”（别的语言都这样）。
// 所以在连接上先看一眼请求行：记下原样的地址，把路径里写法不对的 % 换成 %25 再交给 net/http。
// 为此一个连接只处理一个请求（关掉连接复用）。

type connKey struct{}

type rawConn struct {
	net.Conn
	target  string // 请求行里原样的地址
	pending []byte // 已经改写好、还没交出去的字节
	done    bool   // 请求行已经处理过（或者放弃处理）
}

const requestLineLimit = 65536

func (c *rawConn) Read(p []byte) (int, error) {
	if !c.done {
		buf := make([]byte, 0, 1024)
		chunk := make([]byte, 1024)
		for {
			n, err := c.Conn.Read(chunk)
			buf = append(buf, chunk[:n]...)
			end := bytes.IndexByte(buf, '\n')
			if end >= 0 {
				c.pending = append(c.rewrite(buf[:end]), buf[end:]...)
				break
			}
			if err != nil || len(buf) > requestLineLimit {
				c.pending = buf
				if len(buf) == 0 {
					c.done = true
					return 0, err
				}
				break
			}
		}
		c.done = true
	}
	if len(c.pending) > 0 {
		n := copy(p, c.pending)
		c.pending = c.pending[n:]
		return n, nil
	}
	return c.Conn.Read(p)
}

func rawHex(b byte) bool {
	return (b >= '0' && b <= '9') || (b >= 'a' && b <= 'f') || (b >= 'A' && b <= 'F')
}

// rewrite 处理请求行（不带结尾的换行）：方式 地址 HTTP/1.1。
func (c *rawConn) rewrite(line []byte) []byte {
	first := bytes.IndexByte(line, ' ')
	last := bytes.LastIndexByte(line, ' ')
	if first < 0 || last <= first {
		return line
	}
	target := string(line[first+1 : last])
	c.target = target
	path, query, hasQuery := strings.Cut(target, "?")
	var b bytes.Buffer
	b.Write(line[:first+1])
	for i := 0; i < len(path); i++ {
		b.WriteByte(path[i])
		if path[i] == '%' && (i+2 >= len(path) || !rawHex(path[i+1]) || !rawHex(path[i+2])) {
			b.WriteString("25")
		}
	}
	if hasQuery {
		b.WriteByte('?')
		b.WriteString(query)
	}
	b.Write(line[last:])
	return b.Bytes()
}

type rawListener struct{ net.Listener }

func (l rawListener) Accept() (net.Conn, error) {
	conn, err := l.Listener.Accept()
	if err != nil {
		return nil, err
	}
	return &rawConn{Conn: conn}, nil
}

// HostServe：一直服务，不返回；端口用不了＝出错。
func HostServe(lt *Line, port int64, host string, handler func(*Line, Dict[any]) Dict[any]) {
	lineCheck(lt)
	if port < 0 || port > 65535 {
		Fail("开不了服务：端口要在 0 到 65535 之间")
	}
	ln, err := net.Listen("tcp", net.JoinHostPort(host, strconv.FormatInt(port, 10)))
	if err != nil {
		Fail("开不了服务：" + host + ":" + strconv.FormatInt(port, 10) + " 用不了")
	}
	Log("后端已启动：http://" + host + ":" + strconv.Itoa(ln.Addr().(*net.TCPAddr).Port))
	server := &http.Server{
		Handler:     http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { serveOne(w, r, handler) }),
		ConnContext: func(ctx context.Context, c net.Conn) context.Context { return context.WithValue(ctx, connKey{}, c) },
	}
	server.SetKeepAlivesEnabled(false)
	server.Serve(rawListener{ln})
	select {}
}
''';
