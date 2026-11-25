/// PHP 运行时小库的源码（值的规矩、运算；生成的工程里的 `lc_runtime.php`）。每份工程都一样。
///
/// **没有在真机器上实际运行过**（本机没有 php）：只做了结构检查（test/backend_codegen_langs_test.dart）。凭记忆写的 PHP 函数清单见 docs/api-notes.md。
/// 值的规矩见 backend_ir.dart 的 `kBeRuntimeFns`，改这里的行为要同时改别的语言的小库。
library;

const String kPhpRuntimeSource = r'''
<?php
// LopiCode 后端运行时小库（PHP，只用 PHP 自带的函数，不用装任何包、不用 Composer）：值的规矩、运算。
// 每份生成的工程都一样，不用改；你的接口在 server.php 里。
// 注意：这份 PHP 代码还没有在真机器上实际运行过。

const LC_BODY_LIMIT = 1048576; // 请求内容最多 1MB
const LC_REPEAT_LIMIT = 10000; // “重复”最多做这么多遍
const LC_FETCH_TIMEOUT = 10; // “请求别的网址”最多等 10 秒
const LC_JSON_DEPTH_LIMIT = 64; // 请求内容的 JSON 最多套这么多层

// —— 值：空 / 是否 / 数字（一律 float）/ 文字 / 列表（LcList）/ 对象（LcObj）——

// 对象。字段放在 $f 里（PHP 数组会把 "12" 这种键变成整数 12，读键的时候一律再转回文字）。
final class LcObj
{
    public $f = array();
}

// 列表。项放在 $a 里（一个从 0 起连着编号的 PHP 数组）。包成对象是因为 PHP 数组传来传去是复制的：
// “在末尾加一项”改不到原来那个；对象传的是同一个，和别的语言一样。
final class LcList
{
    public $a = array();

    public function __construct($a = array())
    {
        $this->a = $a;
    }
}

final class LcBadJson extends Exception
{
}

function lc_kind($v)
{
    if ($v === null) {
        return 'null';
    }
    if (is_bool($v)) {
        return 'bool';
    }
    if (is_float($v) || is_int($v)) {
        return 'num';
    }
    if (is_string($v)) {
        return 'text';
    }
    if ($v instanceof LcFn) {
        return 'fn'; // “函数”这种值（积木第 4 版；LcFn 在 lc_lang.php 里）
    }
    return $v instanceof LcList ? 'list' : 'obj';
}

function lc_fin($n)
{
    $n = (float) $n;
    return is_finite($n) ? $n : 0.0;
}

// 转成数字：转不了的当 0。
function lc_to_num($v)
{
    if (is_float($v) || is_int($v)) {
        return lc_fin($v);
    }
    if (is_string($v)) {
        if (!preg_match('/\A[ \t\r\n]*[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?[ \t\r\n]*\z/', $v)) {
            return 0.0;
        }
        return lc_fin((float) trim($v, " \t\r\n"));
    }
    return $v === true ? 1.0 : 0.0;
}

// 数字的写法：整数不带小数点；其余保留 12 位有效数字（正好一半时远离 0，0.1 + 0.2 写成 0.3）。
function lc_fmt_num($n)
{
    $n = (float) $n;
    if (!is_finite($n) || $n == 0.0) {
        return '0';
    }
    if (floor($n) == $n && abs($n) < 1e15) {
        return sprintf('%.0F', $n);
    }
    $sign = $n < 0 ? '-' : '';
    // 先要 41 位有效数字（足够看出第 13 位是不是正好一半），再自己四舍五入到 12 位
    if (!preg_match('/\A([0-9])[.,]([0-9]{40})[eE]([+-]?[0-9]+)\z/', sprintf('%.40e', abs($n)), $m)) {
        return '0';
    }
    $all = $m[1] . $m[2];
    $e = (int) $m[3];
    $head = substr($all, 0, 12);
    if (ord($all[12]) >= ord('5')) {
        $i = 11;
        while ($i >= 0 && $head[$i] === '9') {
            $head[$i] = '0';
            $i--;
        }
        if ($i < 0) {
            $head = '1' . $head;
            $e++;
        } else {
            $head[$i] = chr(ord($head[$i]) + 1);
        }
    }
    $d = rtrim($head, '0');
    $len = strlen($d);
    if ($e >= 15 || $e < -7) {
        return $sign . $d[0] . ($len > 1 ? '.' . substr($d, 1) : '') . 'e' . $e;
    }
    if ($e >= $len - 1) {
        return $sign . $d . str_repeat('0', $e - $len + 1);
    }
    if ($e >= 0) {
        return $sign . substr($d, 0, $e + 1) . '.' . substr($d, $e + 1);
    }
    return $sign . '0.' . str_repeat('0', -$e - 1) . $d;
}

// 文字写成 JSON：只转义 "、\ 和 U+0000–U+001F。
function lc_json_text($s)
{
    static $map = null;
    if ($map === null) {
        $map = array('"' => '\\"', '\\' => '\\\\', "\x08" => '\\b', "\x0c" => '\\f', "\n" => '\\n', "\r" => '\\r', "\t" => '\\t');
        for ($i = 0; $i < 32; $i++) {
            if (!isset($map[chr($i)])) {
                $map[chr($i)] = sprintf('\\u%04x', $i);
            }
        }
    }
    return '"' . strtr((string) $s, $map) . '"';
}

// 对象的键，都是文字，按 Unicode 码点从小到大排好（UTF-8 按字节比就是按码点比）。
function lc_keys($o)
{
    $keys = array();
    foreach ($o->f as $k => $unused) {
        $keys[] = (string) $k;
    }
    sort($keys, SORT_STRING);
    return $keys;
}

// 写成 JSON：对象的键排好序，数字按上面的写法。$exact 是 true 时数字写全（存文件用，读回来一位不差）。
function lc_to_json($v, $exact = false)
{
    switch (lc_kind($v)) {
        case 'null':
            return 'null';
        case 'bool':
            return $v ? 'true' : 'false';
        case 'num':
            return $exact ? lc_exact_num($v) : lc_fmt_num($v);
        case 'text':
            return lc_json_text($v);
        case 'list':
            $parts = array();
            foreach ($v->a as $x) {
                $parts[] = lc_to_json($x, $exact);
            }
            return '[' . implode(',', $parts) . ']';
        case 'fn':
            return 'null'; // 函数写不成 JSON：当空
        default:
            $parts = array();
            foreach (lc_keys($v) as $k) {
                $parts[] = lc_json_text($k) . ':' . lc_to_json($v->f[$k], $exact);
            }
            return '{' . implode(',', $parts) . '}';
    }
}

// 数字写全：17 位有效数字，读回来一定是同一个数。
function lc_exact_num($n)
{
    $n = lc_fin($n);
    if ($n == 0.0) {
        return '0';
    }
    return str_replace(',', '.', sprintf('%.16e', $n));
}

// 转成文字。
function lc_to_text($v)
{
    if ($v === null) {
        return '';
    }
    if ($v instanceof LcFn) {
        return $v->name === '' ? '[函数]' : '[函数 ' . $v->name . ']';
    }
    return is_string($v) ? $v : lc_to_json($v);
}

// 算不算“是”：空、否、0、空文字算“否”。
function lc_truthy($v)
{
    if ($v === null || $v === false || $v === '') {
        return false;
    }
    return !((is_float($v) || is_int($v)) && $v == 0);
}

// “等于”：类型一样直接比；不一样就都转成文字再比。
function lc_eq($a, $b)
{
    $ka = lc_kind($a);
    if ($ka !== lc_kind($b)) {
        return lc_to_text($a) === lc_to_text($b);
    }
    if ($ka === 'list' || $ka === 'obj') {
        return lc_to_json($a) === lc_to_json($b);
    }
    if ($ka === 'fn') { // 两个函数：是同一个，或者是同一个有名字的函数
        return $a === $b || ($a->name !== '' && $a->name === $b->name);
    }
    return $ka === 'num' ? (float) $a === (float) $b : $a === $b;
}

function lc_is_obj($v)
{
    return $v instanceof LcObj;
}

// —— 运算 ——

function lc_add($a, $b)
{
    return lc_fin(lc_to_num($a) + lc_to_num($b));
}

function lc_sub($a, $b)
{
    return lc_fin(lc_to_num($a) - lc_to_num($b));
}

function lc_mul($a, $b)
{
    return lc_fin(lc_to_num($a) * lc_to_num($b));
}

function lc_div($a, $b)
{
    $d = lc_to_num($b);
    return $d == 0.0 ? 0.0 : lc_fin(lc_to_num($a) / $d);
}

// 取余：符号跟被除数（-7 余 3 是 -1）。
function lc_mod($a, $b)
{
    $d = lc_to_num($b);
    return $d == 0.0 ? 0.0 : lc_fin(fmod(lc_to_num($a), $d));
}

function lc_ne($a, $b)
{
    return !lc_eq($a, $b);
}

function lc_lt($a, $b)
{
    return lc_to_num($a) < lc_to_num($b);
}

function lc_le($a, $b)
{
    return lc_to_num($a) <= lc_to_num($b);
}

function lc_gt($a, $b)
{
    return lc_to_num($a) > lc_to_num($b);
}

function lc_ge($a, $b)
{
    return lc_to_num($a) >= lc_to_num($b);
}

function lc_allOf($a, $b)
{
    return lc_truthy($a) && lc_truthy($b);
}

function lc_anyOf($a, $b)
{
    return lc_truthy($a) || lc_truthy($b);
}

function lc_isNot($x)
{
    return !lc_truthy($x);
}

function lc_isNull($x)
{
    return $x === null;
}

function lc_join(...$items)
{
    $out = '';
    foreach ($items as $x) {
        $out .= lc_to_text($x);
    }
    return $out;
}

// 列表的项数 / 文字的字数（按 Unicode 码点：不数 UTF-8 的后续字节）/ 对象的字段数。
function lc_size($x)
{
    switch (lc_kind($x)) {
        case 'list':
            return (float) count($x->a);
        case 'text':
            return (float) (strlen($x) - preg_match_all('/[\x80-\xBF]/', $x));
        case 'obj':
            return (float) count($x->f);
        default:
            return 0.0;
    }
}

// lc_obj("title", "买菜", "done", false) → { title: "买菜", done: false }
function lc_obj(...$pairs)
{
    $o = new LcObj();
    for ($i = 0; $i + 1 < count($pairs); $i += 2) {
        $o->f[(string) $pairs[$i]] = $pairs[$i + 1];
    }
    return $o;
}

function lc_field($o, $key)
{
    if (!($o instanceof LcObj) || !array_key_exists((string) $key, $o->f)) {
        return null;
    }
    return $o->f[(string) $key];
}

function lc_times($x)
{
    $n = lc_to_num($x);
    if ($n < 0) {
        return 0;
    }
    return $n > LC_REPEAT_LIMIT ? LC_REPEAT_LIMIT : (int) $n;
}

function lc_items($x)
{
    return $x instanceof LcList ? $x->a : array();
}

function lc_now()
{
    return gmdate('Y-m-d\TH:i:s\Z');
}

// 写一行到服务的标准输出（php -S 的那个终端）。
function lc_log($x)
{
    $out = @fopen('php://stdout', 'w');
    if ($out === false) {
        error_log(lc_to_text($x));
        return;
    }
    fwrite($out, lc_to_text($x) . "\n");
    fclose($out);
}
''';
