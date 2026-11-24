/// Go 运行时小库的源码（请求别的网址；生成的工程里的 `lc/fetch.go`）。每份工程都一样。源码已经是 gofmt 的规范格式。
library;

const String kGoRuntimeFetchSource = r'''
// LopiCode 后端运行时小库（Go）：请求别的网址。
package lc

import (
	"io"
	"net/http"
	"strings"
	"unicode/utf8"
)

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

const urlKeep = "-._~:/?#[]@!$&'()*+,;="

// encodeURL 把网址里的空格、中文、写法不对的百分号先按 UTF-8 做百分号转义（各语言自己的处理不一样，这里统一）。
func encodeURL(s string) string {
	var b strings.Builder
	for i := 0; i < len(s); i++ {
		c := s[i]
		escaped := c == '%' && i+2 < len(s) && isHex(s[i+1]) && isHex(s[i+2])
		letter := (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
		if escaped || letter || isDigit(c) || strings.IndexByte(urlKeep, c) >= 0 {
			b.WriteByte(c)
		} else {
			b.WriteByte('%')
			b.WriteByte(upperHex[c>>4])
			b.WriteByte(upperHex[c&15])
		}
	}
	return b.String()
}

const upperHex = "0123456789ABCDEF"

var fetchClient = &http.Client{Timeout: fetchTimeout}

// Fetch 请求别的网址：成功（2xx）返回响应的文字；失败、超时、不是 http(s) 网址、网址里带用户名密码一律返回 nil。
func Fetch(method string, url any, data any) any {
	target := toText(url)
	lower := strings.ToLower(target)
	if !strings.HasPrefix(lower, "http://") && !strings.HasPrefix(lower, "https://") {
		return nil
	}
	// 主机那一段带 @（用户名密码）的不请求
	authority := target[strings.Index(target, "://")+3:]
	if end := strings.IndexAny(authority, "/?#"); end >= 0 {
		authority = authority[:end]
	}
	if strings.Contains(authority, "@") {
		return nil
	}
	target = encodeURL(target)
	var payload io.Reader
	verb := http.MethodGet
	if method == "POST" {
		verb = http.MethodPost
		if data != nil {
			payload = strings.NewReader(toJSON(data))
		}
	}
	req, err := http.NewRequest(verb, target, payload)
	if err != nil {
		return nil
	}
	if payload != nil {
		req.Header.Set("Content-Type", "application/json; charset=utf-8")
	}
	res, err := fetchClient.Do(req)
	if err != nil {
		return nil
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode > 299 {
		return nil
	}
	raw, err := io.ReadAll(res.Body)
	if err != nil {
		return nil
	}
	return decodeUTF8(raw)
}
''';
