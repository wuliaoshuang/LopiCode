/// PHP 的语言核心小库（生成的工程里的 `lc_lang.php`）：积木第 4 版新加的操作。只有用到新积木的工程才带这个文件。
///
/// **这份 PHP 代码还没有实际运行过**（本机没有 PHP），只做过文本级的检查；是照别的四种语言的小库一句句对着写的。
/// 函数表和规矩见 lib/lang/rt.dart 的 `kLangRtFns`。
library;

const String kPhpLangRuntimeSource = r'''
<?php
// LopiCode 语言核心小库（PHP）：积木第 4 版新加的操作——类型、数学、文字、列表、字典、JSON、数列。
// 每份生成的工程都一样，不用改。规矩：位置从 0 数；文字按 Unicode 码点算；读不到得空；写到不存在的位置抛错。
// 注意：这份 PHP 代码还没有在真机器上实际运行过。

const LC_RANGE_LIMIT = 10000; // “数列”“重复文字”最多这么多项
const LC_COUNT_LIMIT = 2147483647; // “从…数到…”最多数这么多遍

const LC_E_NOT_LIST = '这不是列表，改不了';
const LC_E_NOT_DICT = '这不是字典，改不了';
const LC_E_NO_ITEM = '列表里没有这个位置';
const LC_E_NOT_INDEXABLE = '这个值不能按位置或键来改';

// 积木运行时出的错（比如往列表里不存在的位置写）。
final class LcError extends RuntimeException
{
}

// 去掉“负零”（各语言写出来不一样）。
function lc_lang_pz($n)
{
    return $n == 0 ? 0.0 : (float) $n;
}

// 位置：数字化后去掉小数部分；大得离谱的夹在 ±2^53 里（转成整数才不会出问题）。
function lc_lang_index($i)
{
    $n = lc_to_num($i);
    if ($n > 9007199254740992.0) {
        return 9007199254740992;
    }
    if ($n < -9007199254740992.0) {
        return -9007199254740992;
    }
    return (int) $n;
}

function lc_lang_clamp($n, $lo, $hi)
{
    return $n < $lo ? $lo : ($n > $hi ? $hi : $n);
}

// 文字拆成一个个字（按 Unicode 码点）。
function lc_lang_chars($s)
{
    $text = lc_to_text($s);
    if ($text === '') {
        return array();
    }
    $cs = preg_split('//u', $text, -1, PREG_SPLIT_NO_EMPTY);
    return $cs === false ? str_split($text) : $cs;
}

// 列表里的那一串值；不是列表就是空的。
function lc_lang_items($x)
{
    return $x instanceof LcList ? $x->a : array();
}

function lc_lang_must_list($x)
{
    if (!($x instanceof LcList)) {
        throw new LcError(LC_E_NOT_LIST);
    }
    return $x;
}

function lc_lang_must_dict($x)
{
    if (!($x instanceof LcObj)) {
        throw new LcError(LC_E_NOT_DICT);
    }
    return $x;
}

// —— 类型 ——

function lc_isType($x, $name)
{
    $k = lc_kind($x);
    $want = $k === 'num' ? 'number' : ($k === 'obj' ? 'dict' : ($k === 'fn' ? 'function' : $k));
    return $want === lc_to_text($name);
}

function lc_toNumber($x)
{
    return lc_to_num($x);
}

function lc_toText($x)
{
    return lc_to_text($x);
}

function lc_toBool($x)
{
    return lc_truthy($x);
}

function lc_copy($x)
{
    if ($x instanceof LcList) {
        return new LcList(array_map('lc_copy', $x->a));
    }
    if ($x instanceof LcObj) {
        $o = new LcObj();
        foreach ($x->f as $k => $v) {
            $o->f[$k] = lc_copy($v);
        }
        return $o;
    }
    return $x;
}

// —— 数学 ——

function lc_pow($a, $b)
{
    $x = lc_to_num($a);
    $y = lc_to_num($b);
    if ($x == 0 && $y < 0) {
        return 0.0;
    }
    return lc_lang_pz(lc_fin(pow($x, $y)));
}

function lc_round($x)
{
    $n = lc_to_num($x);
    $t = $n < 0 ? ceil($n) : floor($n);
    return lc_lang_pz(abs($n - $t) >= 0.5 ? $t + ($n < 0 ? -1.0 : 1.0) : $t);
}

function lc_floor($x)
{
    return lc_lang_pz(floor(lc_to_num($x)));
}

function lc_ceil($x)
{
    return lc_lang_pz(ceil(lc_to_num($x)));
}

function lc_abs($x)
{
    return abs(lc_to_num($x));
}

function lc_sqrt($x)
{
    $n = lc_to_num($x);
    return $n < 0 ? 0.0 : sqrt($n);
}

function lc_max($a, $b)
{
    $x = lc_to_num($a);
    $y = lc_to_num($b);
    return $x >= $y ? $x : $y;
}

function lc_min($a, $b)
{
    $x = lc_to_num($a);
    $y = lc_to_num($b);
    return $x <= $y ? $x : $y;
}

function lc_random($a, $b)
{
    $x = lc_to_num($a);
    $y = lc_to_num($b);
    $x = $x < 0 ? ceil($x) : floor($x);
    $y = $y < 0 ? ceil($y) : floor($y);
    $lo = $x <= $y ? $x : $y;
    $hi = $x <= $y ? $y : $x;
    $r = mt_rand() / (mt_getrandmax() + 1.0);
    return lc_lang_pz($lo + floor($r * ($hi - $lo + 1)));
}

// —— 文字 ——

function lc_charAt($s, $i)
{
    $cs = lc_lang_chars($s);
    $n = lc_lang_index($i);
    return $n >= 0 && $n < count($cs) ? $cs[$n] : null;
}

function lc_substring($s, $from, $to)
{
    $cs = lc_lang_chars($s);
    $a = lc_lang_clamp(lc_lang_index($from), 0, count($cs));
    $b = lc_lang_clamp(lc_lang_index($to), 0, count($cs));
    return $a >= $b ? '' : implode('', array_slice($cs, $a, $b - $a));
}

function lc_contains($s, $sub)
{
    $p = lc_to_text($sub);
    return $p === '' || strpos(lc_to_text($s), $p) !== false;
}

function lc_startsWith($s, $p)
{
    $p = lc_to_text($p);
    return strncmp(lc_to_text($s), $p, strlen($p)) === 0;
}

function lc_endsWith($s, $p)
{
    $p = lc_to_text($p);
    return $p === '' || substr(lc_to_text($s), -strlen($p)) === $p;
}

function lc_indexOf($s, $sub)
{
    $text = lc_to_text($s);
    $p = lc_to_text($sub);
    if ($p === '') {
        return 0.0;
    }
    $at = strpos($text, $p);
    if ($at === false) {
        return -1.0;
    }
    $head = substr($text, 0, $at);
    return (float) (strlen($head) - preg_match_all('/[\x80-\xBF]/', $head));
}

function lc_replace($s, $from, $to)
{
    $f = lc_to_text($from);
    return $f === '' ? lc_to_text($s) : str_replace($f, lc_to_text($to), lc_to_text($s));
}

function lc_split($s, $sep)
{
    $p = lc_to_text($sep);
    return new LcList($p === '' ? lc_lang_chars($s) : explode($p, lc_to_text($s)));
}

function lc_trim($s)
{
    return trim(lc_to_text($s), " \t\r\n");
}

function lc_upper($s)
{
    return strtr(lc_to_text($s), 'abcdefghijklmnopqrstuvwxyz', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
}

function lc_lower($s)
{
    return strtr(lc_to_text($s), 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'abcdefghijklmnopqrstuvwxyz');
}

function lc_repeatText($s, $n)
{
    return str_repeat(lc_to_text($s), lc_lang_clamp(lc_lang_index($n), 0, LC_RANGE_LIMIT));
}

function lc_template($s, $d)
{
    return preg_replace_callback('/\{([^{}]*)\}/', function ($m) use ($d) {
        if ($d instanceof LcObj && array_key_exists($m[1], $d->f)) {
            return lc_to_text($d->f[$m[1]]);
        }
        return $m[0];
    }, lc_to_text($s));
}

// —— 列表 ——

function lc_listOf(...$xs)
{
    return new LcList(array_values($xs));
}

function lc_listGet($xs, $i)
{
    $items = lc_lang_items($xs);
    $n = lc_lang_index($i);
    return $n >= 0 && $n < count($items) ? $items[$n] : null;
}

function lc_listSet($xs, $i, $v)
{
    $list = lc_lang_must_list($xs);
    $n = lc_lang_index($i);
    if ($n < 0 || $n >= count($list->a)) {
        throw new LcError(LC_E_NO_ITEM);
    }
    $list->a[$n] = $v;
}

function lc_listPush($xs, $v)
{
    $list = lc_lang_must_list($xs);
    $list->a[] = $v;
}

function lc_listInsert($xs, $i, $v)
{
    $list = lc_lang_must_list($xs);
    $n = lc_lang_index($i);
    if ($n < 0 || $n > count($list->a)) {
        throw new LcError(LC_E_NO_ITEM);
    }
    array_splice($list->a, $n, 0, array($v));
}

function lc_listRemove($xs, $i)
{
    $list = lc_lang_must_list($xs);
    $n = lc_lang_index($i);
    if ($n < 0 || $n >= count($list->a)) {
        throw new LcError(LC_E_NO_ITEM);
    }
    $gone = array_splice($list->a, $n, 1);
    return $gone[0];
}

function lc_listPop($xs)
{
    if (!($xs instanceof LcList) || count($xs->a) === 0) {
        return null;
    }
    return array_pop($xs->a);
}

function lc_listIndexOf($xs, $v)
{
    foreach (lc_lang_items($xs) as $i => $x) {
        if (lc_eq($x, $v)) {
            return (float) $i;
        }
    }
    return -1.0;
}

function lc_listContains($xs, $v)
{
    return lc_listIndexOf($xs, $v) >= 0;
}

function lc_listSlice($xs, $from, $to)
{
    $items = lc_lang_items($xs);
    $a = lc_lang_clamp(lc_lang_index($from), 0, count($items));
    $b = lc_lang_clamp(lc_lang_index($to), 0, count($items));
    return new LcList($a >= $b ? array() : array_slice($items, $a, $b - $a));
}

function lc_listConcat($a, $b)
{
    return new LcList(array_merge(lc_lang_items($a), lc_lang_items($b)));
}

function lc_listReverse($xs)
{
    return new LcList(array_reverse(lc_lang_items($xs)));
}

// 数字排在前面、按大小；其余的文字化后按码点；一样的保持原来的先后。
function lc_listSort($xs)
{
    $keyed = array();
    foreach (lc_lang_items($xs) as $i => $v) {
        $isNum = is_float($v) || is_int($v);
        $keyed[] = array($v, $isNum, $isNum ? (float) $v : 0.0, $isNum ? '' : lc_to_text($v), $i);
    }
    usort($keyed, function ($x, $y) {
        if ($x[1] && $y[1]) {
            $c = $x[2] < $y[2] ? -1 : ($x[2] > $y[2] ? 1 : 0);
        } elseif ($x[1] !== $y[1]) {
            $c = $x[1] ? -1 : 1;
        } else {
            $c = strcmp($x[3], $y[3]);
            $c = $c < 0 ? -1 : ($c > 0 ? 1 : 0);
        }
        return $c !== 0 ? $c : $x[4] - $y[4];
    });
    $out = array();
    foreach ($keyed as $k) {
        $out[] = $k[0];
    }
    return new LcList($out);
}

function lc_listJoin($xs, $sep)
{
    return implode(lc_to_text($sep), array_map('lc_to_text', lc_lang_items($xs)));
}

// “从…数到…”要做几遍。
function lc_countSteps($from, $to, $step)
{
    $a = lc_to_num($from);
    $s = lc_to_num($step);
    if ($s == 0) {
        return 0;
    }
    $d = (lc_to_num($to) - $a) / $s;
    if (!($d >= 0)) {
        return 0;
    }
    if ($d >= LC_COUNT_LIMIT) {
        return LC_COUNT_LIMIT;
    }
    $n = (int) floor($d + 1e-9) + 1;
    return $n > LC_COUNT_LIMIT ? LC_COUNT_LIMIT : $n;
}

function lc_range($from, $to, $step)
{
    $a = lc_to_num($from);
    $s = lc_to_num($step);
    $n = min(lc_countSteps($a, $to, $s), LC_RANGE_LIMIT);
    $out = array();
    for ($k = 0; $k < $n; $k++) {
        $out[] = $a + $k * $s;
    }
    return new LcList($out);
}

// —— 字典 ——

function lc_dictOf(...$pairs)
{
    $o = new LcObj();
    for ($i = 0; $i + 1 < count($pairs); $i += 2) {
        $o->f[lc_to_text($pairs[$i])] = $pairs[$i + 1];
    }
    return $o;
}

function lc_dictHas($d, $k)
{
    return $d instanceof LcObj && array_key_exists(lc_to_text($k), $d->f);
}

function lc_dictGet($d, $k)
{
    return lc_dictHas($d, $k) ? $d->f[lc_to_text($k)] : null;
}

function lc_dictSet($d, $k, $v)
{
    $dict = lc_lang_must_dict($d);
    $dict->f[lc_to_text($k)] = $v;
}

function lc_dictRemove($d, $k)
{
    $dict = lc_lang_must_dict($d);
    unset($dict->f[lc_to_text($k)]);
}

function lc_dictKeys($d)
{
    return new LcList($d instanceof LcObj ? lc_keys($d) : array());
}

function lc_dictValues($d)
{
    $out = array();
    if ($d instanceof LcObj) {
        foreach (lc_keys($d) as $k) {
            $out[] = $d->f[$k];
        }
    }
    return new LcList($out);
}

function lc_dictPairs($d)
{
    $out = array();
    if ($d instanceof LcObj) {
        foreach (lc_keys($d) as $k) {
            $out[] = new LcList(array($k, $d->f[$k]));
        }
    }
    return new LcList($out);
}

function lc_dictMerge($a, $b)
{
    $o = new LcObj();
    foreach (array($a, $b) as $d) {
        if ($d instanceof LcObj) {
            foreach ($d->f as $k => $v) {
                $o->f[$k] = $v;
            }
        }
    }
    return $o;
}

// —— 列表 / 字典 / 文字通用 ——

function lc_item($x, $k)
{
    if ($x instanceof LcList) {
        return lc_listGet($x, $k);
    }
    if ($x instanceof LcObj) {
        return lc_dictGet($x, $k);
    }
    return is_string($x) ? lc_charAt($x, $k) : null;
}

function lc_setItem($x, $k, $v)
{
    if ($x instanceof LcList) {
        lc_listSet($x, $k, $v);
    } elseif ($x instanceof LcObj) {
        lc_dictSet($x, $k, $v);
    } else {
        throw new LcError(LC_E_NOT_INDEXABLE);
    }
}

// —— JSON ——

function lc_toJson($x)
{
    return lc_to_json($x);
}

function lc_fromJson($s)
{
    return lc_parse_json(lc_to_text($s));
}
''';
