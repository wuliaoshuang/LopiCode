/// 规矩版本 2 的小库·Go·第四份（`lc/io.go`）：随机字节、文件、请求别的网址。
/// 细则见 docs/blocks-v5-parts/C-library-system.md 9.1、9.2 和 B-gen-notes.md 第 14 节。只用 Go 自带的包。
library;

const String kRt2GoIo = r'''
// LopiCode 积木的小库（Go，严格规矩）·第四份。由 LopiCode 生成，别手改。

package lc

import (
	"crypto/rand"
	"errors"
	"io"
	"io/fs"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

func HostRandomBytes(n int64) *List[int64] {
	if n < 1 || n > 1024 {
		Fail("随机字节的个数要在 1 到 1024 之间")
	}
	raw := make([]byte, n)
	if _, err := rand.Read(raw); err != nil {
		Fail("拿不到随机字节")
	}
	out := &List[int64]{Items: make([]int64, n)}
	for i, b := range raw {
		out.Items[i] = int64(b)
	}
	return out
}

// —— 文件：路径相对工程文件夹（程序跑起来时所在的文件夹） ——
var driveRe = regexp.MustCompile(`^[A-Za-z]:`)

func filePath(p string) string {
	bad := p == "" || p[0] == '/' || p[0] == '\\' || driveRe.MatchString(p)
	for _, seg := range strings.FieldsFunc(p, func(r rune) bool { return r == '/' || r == '\\' }) {
		bad = bad || seg == ".."
	}
	if bad {
		Fail("路径不对：只能用工程文件夹里面的相对路径")
	}
	wd, _ := os.Getwd()
	return filepath.Join(wd, p)
}
func FileRead(p string) string {
	raw, err := os.ReadFile(filePath(p))
	if errors.Is(err, fs.ErrNotExist) {
		Fail("读不了文件：没有「" + p + "」")
	}
	if err != nil {
		Fail("读不了文件：「" + p + "」")
	}
	if !utf8.Valid(raw) {
		Fail("读不了文件：「" + p + "」不是 UTF-8 文字")
	}
	return string(raw)
}
func FileWrite(p string, text string) {
	full := filePath(p)
	tmp := full + ".lctmp" + strconv.Itoa(os.Getpid())
	err := os.MkdirAll(filepath.Dir(full), 0o777)
	if err == nil {
		err = os.WriteFile(tmp, []byte(text), 0o666)
	}
	if err == nil {
		err = os.Rename(tmp, full)
	}
	if err != nil {
		os.Remove(tmp)
		Fail("写不了文件：「" + p + "」")
	}
}
func FileExists(p string) bool {
	_, err := os.Stat(filePath(p))
	return err == nil
}
func FileList(p string) *List[string] {
	entries, err := os.ReadDir(filePath(p))
	if err != nil {
		Fail("列不了文件夹：「" + p + "」")
	}
	out := &List[string]{Items: []string{}}
	for _, e := range entries {
		out.Items = append(out.Items, e.Name())
	}
	sort.Strings(out.Items)
	return out
}
func FileRemove(p string) {
	full := filePath(p)
	info, err := os.Stat(full)
	if err != nil || !info.Mode().IsRegular() || os.Remove(full) != nil {
		Fail("删不了文件：「" + p + "」")
	}
}

// —— 请求别的网址 ——
// decodeUTF8 把字节读成文字，坏的地方换成 U+FFFD（换法和浏览器的标准一致：一段读不下去的开头算一个）。
func decodeUTF8(raw []byte) string {
	if utf8.Valid(raw) {
		return string(raw)
	}
	var b strings.Builder
	for i := 0; i < len(raw); {
		c := raw[i]
		need, lo, hi := 0, byte(0x80), byte(0xBF)
		switch {
		case c < 0x80:
			b.WriteByte(c)
			i++
			continue
		case c >= 0xC2 && c <= 0xDF:
			need = 1
		case c >= 0xE0 && c <= 0xEF:
			need = 2
			if c == 0xE0 {
				lo = 0xA0
			} else if c == 0xED {
				hi = 0x9F
			}
		case c >= 0xF0 && c <= 0xF4:
			need = 3
			if c == 0xF0 {
				lo = 0x90
			} else if c == 0xF4 {
				hi = 0x8F
			}
		}
		j := i + 1
		for got := 0; got < need && j < len(raw) && raw[j] >= lo && raw[j] <= hi; got++ {
			j++
			lo, hi = 0x80, 0xBF
		}
		if need > 0 && j == i+1+need {
			b.Write(raw[i:j])
		} else {
			b.WriteRune(utf8.RuneError)
		}
		i = j
	}
	return b.String()
}

const urlKeep = "-._~:/?[]@!$&'()*+,;="
const upperHex = "0123456789ABCDEF"

func isHex(c byte) bool {
	return (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f')
}

// encodeURL：网址里的空格、中文、写法不对的百分号先按 UTF-8 做百分号转义（各语言自己的处理不一样，这里统一）；# 后面的不发。
func encodeURL(s string) string {
	if hash := strings.IndexByte(s, '#'); hash >= 0 {
		s = s[:hash]
	}
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		escaped := c == '%' && i+2 < len(s) && isHex(s[i+1]) && isHex(s[i+2])
		letter := (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')
		if escaped || letter || strings.IndexByte(urlKeep, c) >= 0 {
			b.WriteByte(c)
		} else {
			b.WriteByte('%')
			b.WriteByte(upperHex[c>>4])
			b.WriteByte(upperHex[c&15])
		}
	}
	return b.String()
}

var fetchMethods = map[string]bool{"GET": true, "HEAD": true, "POST": true, "PUT": true, "PATCH": true, "DELETE": true, "OPTIONS": true}
var fetchSkip = map[string]bool{"host": true, "content-length": true, "connection": true, "expect": true, "upgrade": true}

func HostFetch(method string, url string, headers Dict[string], body *string, timeoutMs int64) Dict[any] {
	lower := strings.ToLower(url)
	if !strings.HasPrefix(lower, "http://") && !strings.HasPrefix(lower, "https://") {
		Fail("请求不了：网址要以 http:// 或 https:// 开头")
	}
	if !fetchMethods[method] {
		Fail("请求不了：不认识的方式「" + method + "」")
	}
	if timeoutMs <= 0 {
		Fail("请求不了：超时毫秒要大于 0")
	}
	var payload io.Reader
	hasBody := body != nil && method != "GET" && method != "HEAD"
	if hasBody {
		payload = strings.NewReader(*body)
	}
	req, err := http.NewRequest(method, encodeURL(url), payload)
	if err != nil {
		Fail("请求不了：连不上")
	}
	hasType, hasAgent := false, false
	for _, k := range Keys(headers) {
		low := strings.ToLower(k)
		if fetchSkip[low] {
			continue
		}
		hasType = hasType || low == "content-type"
		hasAgent = hasAgent || low == "user-agent"
		req.Header.Set(k, headers[k])
	}
	if !hasAgent {
		req.Header.Set("User-Agent", "LopiCode")
	}
	if hasBody && !hasType {
		req.Header.Set("Content-Type", "text/plain; charset=utf-8")
	}
	client := &http.Client{Timeout: time.Duration(timeoutMs) * time.Millisecond}
	res, err := client.Do(req)
	var raw []byte
	if err == nil {
		defer res.Body.Close()
		raw, err = io.ReadAll(res.Body)
	}
	if err != nil {
		if os.IsTimeout(err) {
			Fail("请求超时了")
		}
		Fail("请求不了：连不上")
	}
	back := Dict[any]{}
	for k, vs := range res.Header {
		back[strings.ToLower(k)] = strings.Join(vs, ", ")
	}
	return Dict[any]{"status": float64(res.StatusCode), "headers": back, "body": decodeUTF8(raw)}
}
''';
