/// Go 运行时小库的源码（请求、响应、路由与启动；生成的工程里的 `lc/server.go`）。每份工程都一样。
///
/// 用标准库的 net/http。它碰到地址里写法不对的百分号（`%zz`）会直接回 400，所以小库在连接上先看一眼请求行、
/// 记下原样的地址（见源码里“请求行里写法不对的百分号”一段）。源码已经是 gofmt 的规范格式。
library;

const String kGoRuntimeServerSource = r'''
// LopiCode 后端运行时小库（Go）：请求、响应、路由与启动。
package lc

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"strconv"
	"strings"
	"unicode/utf8"
)

// —— 请求 ——

func isHex(c byte) bool {
	return isDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

func unhex(c byte) byte {
	switch {
	case isDigit(c):
		return c - '0'
	case c >= 'a':
		return c - 'a' + 10
	}
	return c - 'A' + 10
}

// pct 做百分号解码；写法不对（%zz、解出来不是合法 UTF-8）就原样返回。
func pct(s string) string {
	if !strings.Contains(s, "%") {
		return s
	}
	out := make([]byte, 0, len(s))
	for i := 0; i < len(s); i++ {
		if s[i] != '%' {
			out = append(out, s[i])
			continue
		}
		if i+2 >= len(s) || !isHex(s[i+1]) || !isHex(s[i+2]) {
			return s
		}
		out = append(out, unhex(s[i+1])<<4|unhex(s[i+2]))
		i += 2
	}
	if !utf8.Valid(out) {
		return s
	}
	return string(out)
}

func parseQuery(raw string) map[string]string {
	out := map[string]string{}
	for _, part := range strings.Split(raw, "&") {
		if part == "" {
			continue
		}
		key, value, _ := strings.Cut(part, "=")
		key = pct(strings.ReplaceAll(key, "+", " "))
		value = pct(strings.ReplaceAll(value, "+", " "))
		if _, seen := out[key]; !seen {
			out[key] = value
		}
	}
	return out
}

// norm 把解出来的 JSON 收拾干净：数字都变成 float64（超出范围的当 0）；套得太深的不要（ok 是 false）。
func norm(v any, depth int) (any, bool) {
	switch x := v.(type) {
	case json.Number:
		n, _ := strconv.ParseFloat(string(x), 64)
		return fin(n), true
	case []any:
		if depth >= jsonDepthLimit {
			return nil, false
		}
		for i, item := range x {
			clean, ok := norm(item, depth+1)
			if !ok {
				return nil, false
			}
			x[i] = clean
		}
		return NewList(x), true
	case map[string]any:
		if depth >= jsonDepthLimit {
			return nil, false
		}
		for k, item := range x {
			clean, ok := norm(item, depth+1)
			if !ok {
				return nil, false
			}
			x[k] = clean
		}
		return x, true
	}
	return v, true
}

func parseBody(raw []byte) any {
	if len(raw) == 0 || !utf8.Valid(raw) || !json.Valid(raw) {
		return nil
	}
	dec := json.NewDecoder(bytes.NewReader(raw))
	dec.UseNumber()
	var v any
	if dec.Decode(&v) != nil {
		return nil
	}
	clean, ok := norm(v, 0)
	if !ok {
		return nil
	}
	return clean
}

// Request 是一次请求。
type Request struct {
	params   map[string]string
	rawQuery string
	query    map[string]string
	header   http.Header
	host     string
	rawBody  []byte
	parsed   bool
	body     any
}

func PathParam(req *Request, name string) any {
	if v, ok := req.params[name]; ok {
		return v
	}
	return nil
}

func Query(req *Request, name string) any {
	if req.query == nil {
		req.query = parseQuery(req.rawQuery)
	}
	if v, ok := req.query[name]; ok {
		return v
	}
	return nil
}

func Body(req *Request) any {
	if !req.parsed {
		req.parsed = true
		req.body = parseBody(req.rawBody)
	}
	return req.body
}

func BodyField(req *Request, name string) any {
	return Field(Body(req), name)
}

// latin1 把请求头里的字节按 ISO-8859-1 读成文字（和别的语言一致；纯英文时不变）。
func latin1(s string) string {
	ascii := true
	for i := 0; i < len(s); i++ {
		if s[i] >= 0x80 {
			ascii = false
			break
		}
	}
	if ascii {
		return s
	}
	runes := make([]rune, len(s))
	for i := 0; i < len(s); i++ {
		runes[i] = rune(s[i])
	}
	return string(runes)
}

func Header(req *Request, name string) any {
	if strings.EqualFold(name, "Host") {
		// Go 把 Host 单独放，不在请求头的表里
		if req.host == "" {
			return nil
		}
		return latin1(req.host)
	}
	values := req.header.Values(name)
	if len(values) == 0 {
		return nil
	}
	return latin1(strings.Join(values, ", "))
}

// —— 响应 ——

// Response 是一个响应。接口函数返回 nil 表示“没有碰到返回积木”（204）。
type Response struct {
	status      int
	contentType string
	body        []byte
}

func statusOf(v any) int {
	n := toNum(v)
	if n >= 200 && n < 600 {
		return int(n)
	}
	return 200
}

func SendJson(status any, value any) *Response {
	return &Response{statusOf(status), "application/json; charset=utf-8", []byte(toJSON(value))}
}

func SendText(status any, value any) *Response {
	return &Response{statusOf(status), "text/plain; charset=utf-8", []byte(toText(value))}
}

func errorResponse(status int, message string) *Response {
	return SendJson(float64(status), Obj("error", message))
}

func write(w http.ResponseWriter, out *Response) {
	h := w.Header()
	h.Set("Access-Control-Allow-Origin", "*")
	if out.status == 204 || out.status == 304 {
		w.WriteHeader(out.status)
		return
	}
	h.Set("Content-Type", out.contentType)
	h.Set("Content-Length", strconv.Itoa(len(out.body)))
	w.WriteHeader(out.status)
	_, _ = w.Write(out.body) // 对方已经断开时写不进去，不用管
}

// —— 路由与启动 ——

// Handler 是一个接口的处理函数。
type Handler func(req *Request) *Response

type routeEntry struct {
	method   string
	segments []string
	handler  Handler
}

var routes []routeEntry

func split(path string) []string {
	out := []string{}
	for _, s := range strings.Split(path, "/") {
		if s != "" {
			out = append(out, s)
		}
	}
	return out
}

// Route 登记一个接口。path 里的 :名字 是路径参数。
func Route(method string, path string, handler Handler) {
	routes = append(routes, routeEntry{method, split(path), handler})
}

// match：路径对得上就返回参数表，否则 nil。
func match(pattern []string, segments []string) map[string]string {
	if len(pattern) != len(segments) {
		return nil
	}
	params := map[string]string{}
	for i, want := range pattern {
		if strings.HasPrefix(want, ":") {
			params[want[1:]] = segments[i]
		} else if want != segments[i] {
			return nil
		}
	}
	return params
}

func run(handler Handler, req *Request) (out *Response) {
	defer func() {
		if problem := recover(); problem != nil {
			fmt.Fprintln(os.Stderr, "接口里出错：", problem)
			out = errorResponse(500, "服务器内部出错")
		}
	}()
	out = handler(req)
	if out == nil {
		// 没有碰到“返回”积木：204 空响应
		out = &Response{status: 204}
	}
	return out
}

func handle(w http.ResponseWriter, r *http.Request) {
	if r.ContentLength > bodyLimit {
		w.Header().Set("Connection", "close")
		write(w, errorResponse(413, "请求内容太大"))
		return
	}
	rawBody, err := io.ReadAll(io.LimitReader(r.Body, bodyLimit+1))
	if err != nil {
		rawBody = nil
	}
	if len(rawBody) > bodyLimit {
		w.Header().Set("Connection", "close")
		write(w, errorResponse(413, "请求内容太大"))
		return
	}
	if r.Method == http.MethodOptions {
		// 浏览器跨域调用前的“预检”
		h := w.Header()
		h.Set("Access-Control-Allow-Origin", "*")
		h.Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
		h.Set("Access-Control-Allow-Headers", "*")
		w.WriteHeader(204)
		return
	}
	// 用请求行里原样的地址（Go 自己解过的那份会把写法不对的百分号拒掉）
	target := r.RequestURI
	if conn, ok := r.Context().Value(connKey{}).(*rawConn); ok && conn.target != "" {
		target = conn.target
	}
	rawPath, rawQuery, _ := strings.Cut(target, "?")
	segments := split(rawPath)
	for i, s := range segments {
		segments[i] = pct(s)
	}
	pathMatched := false
	for _, entry := range routes {
		params := match(entry.segments, segments)
		if params == nil {
			continue
		}
		pathMatched = true
		if entry.method != r.Method {
			continue
		}
		req := &Request{params: params, rawQuery: rawQuery, header: r.Header, host: r.Host, rawBody: rawBody}
		write(w, run(entry.handler, req))
		return
	}
	if pathMatched {
		write(w, errorResponse(405, "这个地址不支持这种请求方式"))
	} else {
		write(w, errorResponse(404, "没有这个接口"))
	}
}

// —— 请求行里写法不对的百分号 ——
//
// Go 的 net/http 碰到地址里有 %zz 这种写法会直接回 400，到不了我们的代码；别的语言的规矩是“原样保留”。
// 所以在连接上先看一眼请求行：记下原样的地址，把路径里写法不对的 % 换成 %25 再交给 net/http。
// （为此关掉了连接复用：一个连接只处理一个请求。）

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

// rewrite 处理请求行（不带结尾的换行）：`方式 地址 HTTP/1.1`。
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
		if path[i] == '%' && (i+2 >= len(path) || !isHex(path[i+1]) || !isHex(path[i+2])) {
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

// Start 启动服务。端口先看环境变量 PORT，没有就用 defaultPort；HOST 默认 0.0.0.0（所有网卡）。
func Start(defaultPort int) {
	port := defaultPort
	if env := os.Getenv("PORT"); len(env) >= 1 && len(env) <= 5 && strings.Trim(env, "0123456789") == "" {
		if n, _ := strconv.Atoi(env); n <= 65535 {
			port = n
		}
	}
	host := os.Getenv("HOST")
	if host == "" {
		host = "0.0.0.0"
	}
	listener, err := net.Listen("tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err != nil {
		fmt.Fprintln(os.Stderr, "启动失败：", err)
		os.Exit(1)
	}
	server := &http.Server{
		Handler: http.HandlerFunc(handle),
		ConnContext: func(ctx context.Context, conn net.Conn) context.Context {
			return context.WithValue(ctx, connKey{}, conn)
		},
	}
	server.SetKeepAlivesEnabled(false)
	say("后端已启动：http://" + host + ":" + strconv.Itoa(listener.Addr().(*net.TCPAddr).Port))
	if err := server.Serve(rawListener{listener}); err != nil {
		fmt.Fprintln(os.Stderr, "服务停了：", err)
		os.Exit(1)
	}
}
''';
