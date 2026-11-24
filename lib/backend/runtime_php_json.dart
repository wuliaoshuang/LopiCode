/// PHP 运行时小库的源码（JSON 解析；生成的工程里的 `lc_json.php`）。每份工程都一样。
///
/// **没有在真机器上实际运行过**（本机没有 php）：只做了结构检查（test/backend_codegen_langs_test.dart）。凭记忆写的 PHP 函数清单见 docs/api-notes.md。
/// 值的规矩见 backend_ir.dart 的 `kBeRuntimeFns`，改这里的行为要同时改别的语言的小库。
library;

const String kPhpRuntimeJsonSource = r'''
<?php
// LopiCode 后端运行时小库（PHP）：JSON 解析。每份生成的工程都一样，不用改。
// 注意：这份 PHP 代码还没有在真机器上实际运行过。

// —— JSON 解析（自己写的：PHP 自带的 json_decode 分不清空列表和空对象、碰到半个表情符号的转义会整份报错）——

// 把一个码点写成 UTF-8。
function lc_utf8($cp)
{
    if ($cp < 0x80) {
        return chr($cp);
    }
    if ($cp < 0x800) {
        return chr(0xC0 | ($cp >> 6)) . chr(0x80 | ($cp & 0x3F));
    }
    if ($cp < 0x10000) {
        return chr(0xE0 | ($cp >> 12)) . chr(0x80 | (($cp >> 6) & 0x3F)) . chr(0x80 | ($cp & 0x3F));
    }
    return chr(0xF0 | ($cp >> 18)) . chr(0x80 | (($cp >> 12) & 0x3F)) . chr(0x80 | (($cp >> 6) & 0x3F)) . chr(0x80 | ($cp & 0x3F));
}

// 是不是合法的 UTF-8。
function lc_is_utf8($s)
{
    return preg_match('//u', $s) === 1;
}

final class LcJsonParser
{
    private $s;
    private $n;
    public $at = 0;

    public function __construct($s)
    {
        $this->s = $s;
        $this->n = strlen($s);
    }

    private function peek()
    {
        if ($this->at >= $this->n) {
            throw new LcBadJson('不是合法的 JSON');
        }
        return $this->s[$this->at];
    }

    public function blank()
    {
        $this->at += strspn($this->s, " \t\r\n", $this->at);
    }

    public function done()
    {
        return $this->at === $this->n;
    }

    private function word($w, $value)
    {
        if (substr($this->s, $this->at, strlen($w)) !== $w) {
            throw new LcBadJson('不是合法的 JSON');
        }
        $this->at += strlen($w);
        return $value;
    }

    public function value($depth)
    {
        switch ($this->peek()) {
            case '{':
                return $this->object($depth + 1);
            case '[':
                return $this->items($depth + 1);
            case '"':
                return $this->text();
            case 't':
                return $this->word('true', true);
            case 'f':
                return $this->word('false', false);
            case 'n':
                return $this->word('null', null);
            default:
                return $this->number();
        }
    }

    private function object($depth)
    {
        if ($depth > LC_JSON_DEPTH_LIMIT) {
            throw new LcBadJson('JSON 套得太深');
        }
        $out = new LcObj();
        $this->at++;
        $this->blank();
        if ($this->peek() === '}') {
            $this->at++;
            return $out;
        }
        while (true) {
            $this->blank();
            if ($this->peek() !== '"') {
                throw new LcBadJson('不是合法的 JSON');
            }
            $key = $this->text();
            $this->blank();
            if ($this->peek() !== ':') {
                throw new LcBadJson('不是合法的 JSON');
            }
            $this->at++;
            $this->blank();
            $out->f[$key] = $this->value($depth); // 键重复时后面的盖掉前面的
            $this->blank();
            $c = $this->peek();
            $this->at++;
            if ($c === '}') {
                return $out;
            }
            if ($c !== ',') {
                throw new LcBadJson('不是合法的 JSON');
            }
        }
    }

    private function items($depth)
    {
        if ($depth > LC_JSON_DEPTH_LIMIT) {
            throw new LcBadJson('JSON 套得太深');
        }
        $out = array();
        $this->at++;
        $this->blank();
        if ($this->peek() === ']') {
            $this->at++;
            return $out;
        }
        while (true) {
            $this->blank();
            $out[] = $this->value($depth);
            $this->blank();
            $c = $this->peek();
            $this->at++;
            if ($c === ']') {
                return $out;
            }
            if ($c !== ',') {
                throw new LcBadJson('不是合法的 JSON');
            }
        }
    }

    // 读 \uXXXX 里的四位十六进制（$this->at 指在第一位上）。
    private function hex4()
    {
        $h = substr($this->s, $this->at, 4);
        if (strlen($h) !== 4 || strspn($h, '0123456789abcdefABCDEF') !== 4) {
            throw new LcBadJson('不是合法的 JSON');
        }
        $this->at += 4;
        return hexdec($h);
    }

    private function text()
    {
        static $simple = array('"' => '"', '\\' => '\\', '/' => '/', 'b' => "\x08", 'f' => "\x0c", 'n' => "\n", 'r' => "\r", 't' => "\t");
        $out = '';
        $this->at++;
        while (true) {
            // 一口气读到下一个引号、反斜杠或控制字符
            $plain = strcspn($this->s, "\"\\\x00\x01\x02\x03\x04\x05\x06\x07\x08\x09\x0a\x0b\x0c\x0d\x0e\x0f\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1a\x1b\x1c\x1d\x1e\x1f", $this->at);
            $out .= substr($this->s, $this->at, $plain);
            $this->at += $plain;
            $c = $this->peek();
            $this->at++;
            if ($c === '"') {
                return $out;
            }
            if ($c !== '\\') {
                throw new LcBadJson('不是合法的 JSON'); // 文字里不许有原样的控制字符
            }
            $e = $this->peek();
            $this->at++;
            if (isset($simple[$e])) {
                $out .= $simple[$e];
                continue;
            }
            if ($e !== 'u') {
                throw new LcBadJson('不是合法的 JSON');
            }
            $code = $this->hex4();
            if ($code >= 0xD800 && $code <= 0xDBFF) {
                // 前半个表情符号：后面紧跟着后半个才算数，否则换成 U+FFFD
                $save = $this->at;
                if (substr($this->s, $this->at, 2) === '\\u') {
                    $this->at += 2;
                    $low = $this->hex4();
                    if ($low >= 0xDC00 && $low <= 0xDFFF) {
                        $out .= lc_utf8(0x10000 + (($code - 0xD800) << 10) + ($low - 0xDC00));
                        continue;
                    }
                }
                $this->at = $save;
                $out .= "\xEF\xBF\xBD";
            } elseif ($code >= 0xDC00 && $code <= 0xDFFF) {
                $out .= "\xEF\xBF\xBD";
            } else {
                $out .= lc_utf8($code);
            }
        }
    }

    private function digits()
    {
        $count = strspn($this->s, '0123456789', $this->at);
        $this->at += $count;
        return $count;
    }

    private function number()
    {
        $from = $this->at;
        if ($this->peek() === '-') {
            $this->at++;
        }
        if ($this->peek() === '0') {
            $this->at++;
        } elseif ($this->digits() === 0) {
            throw new LcBadJson('不是合法的 JSON');
        }
        if ($this->at < $this->n && $this->s[$this->at] === '.') {
            $this->at++;
            if ($this->digits() === 0) {
                throw new LcBadJson('不是合法的 JSON');
            }
        }
        if ($this->at < $this->n && ($this->s[$this->at] === 'e' || $this->s[$this->at] === 'E')) {
            $this->at++;
            if ($this->at < $this->n && ($this->s[$this->at] === '+' || $this->s[$this->at] === '-')) {
                $this->at++;
            }
            if ($this->digits() === 0) {
                throw new LcBadJson('不是合法的 JSON');
            }
        }
        // 超出范围的数（1e400）是无穷大，当 0
        return lc_fin((float) substr($this->s, $from, $this->at - $from));
    }
}

// 按 JSON 解出来；没有内容、不是合法 UTF-8、不是合法 JSON、套得太深 → null。
function lc_parse_json($raw)
{
    if (!is_string($raw) || $raw === '' || !lc_is_utf8($raw)) {
        return null;
    }
    try {
        $p = new LcJsonParser($raw);
        $p->blank();
        $v = $p->value(0);
        $p->blank();
        return $p->done() ? $v : null;
    } catch (LcBadJson $e) {
        return null;
    }
}
''';
