/// PHP 语言核心小库里“函数”那一部分（积木第 4 版·第 2 阶段）：函数值、调用、拿函数当参数的 8 个列表操作。
/// 接在 `kPhpLangRuntimeSource` 后面，同一个文件（`lc_lang.php`）。2026-11-26 起在开发机上用 PHP 8.3 真跑（语言核心一致性测试）。
/// 规矩见 lib/lang/rt.dart；五种语言要一起改。
library;

const String kPhpLangFuncSource = r'''
// —— 函数（第 2 阶段）——

const LC_E_NOT_FUNCTION = '这不是函数，不能调用';
const LC_E_ARG_COUNT = '调用函数时给的参数个数对不上';

// “函数”这种值：名字、最少 / 最多收几个参数（最多是 -1＝不限）、实现（匿名函数，或有名字的函数的名字）。
final class LcFn
{
    public $name;
    public $min;
    public $max;
    public $impl;

    public function __construct($name, $min, $max, $impl)
    {
        $this->name = $name;
        $this->min = $min;
        $this->max = $max;
        $this->impl = $impl;
    }
}

function lc_fn($name, $min, $max, $impl)
{
    return new LcFn($name, $min, $max, $impl);
}

function lc_need_fn($f)
{
    if (!($f instanceof LcFn)) {
        throw new LcError(LC_E_NOT_FUNCTION);
    }
}

// 调一个函数值：不是函数、参数个数对不上 → 抛错。没有返回值的函数得空。
function lc_call($f, ...$args)
{
    lc_need_fn($f);
    $n = count($args);
    if ($n < $f->min || ($f->max >= 0 && $n > $f->max)) {
        throw new LcError(LC_E_ARG_COUNT);
    }
    return call_user_func_array($f->impl, $args);
}

// 开始时把列表抄一份再走（PHP 数组赋值就是抄一份）：回调里改了原来的列表也不影响这一趟。
function lc_lang_each($xs, $f)
{
    lc_need_fn($f);
    return lc_lang_items($xs);
}

function lc_listMap($xs, $f)
{
    $out = array();
    foreach (lc_lang_each($xs, $f) as $x) {
        $out[] = lc_call($f, $x);
    }
    return new LcList($out);
}

function lc_listFilter($xs, $f)
{
    $out = array();
    foreach (lc_lang_each($xs, $f) as $x) {
        if (lc_truthy(lc_call($f, $x))) {
            $out[] = $x;
        }
    }
    return new LcList($out);
}

function lc_listReduce($xs, $f, $init)
{
    $acc = $init;
    foreach (lc_lang_each($xs, $f) as $x) {
        $acc = lc_call($f, $acc, $x);
    }
    return $acc;
}

function lc_listFind($xs, $f)
{
    foreach (lc_lang_each($xs, $f) as $x) {
        if (lc_truthy(lc_call($f, $x))) {
            return $x;
        }
    }
    return null;
}

function lc_listEvery($xs, $f)
{
    foreach (lc_lang_each($xs, $f) as $x) {
        if (!lc_truthy(lc_call($f, $x))) {
            return false;
        }
    }
    return true;
}

function lc_listSome($xs, $f)
{
    foreach (lc_lang_each($xs, $f) as $x) {
        if (lc_truthy(lc_call($f, $x))) {
            return true;
        }
    }
    return false;
}

function lc_listEach($xs, $f)
{
    foreach (lc_lang_each($xs, $f) as $x) {
        lc_call($f, $x);
    }
}

// 按 f(项) 给的分从小到大：分是数字的排前面、按大小；其余的文字化后按码点；一样的保持原来的先后。
function lc_listSortBy($xs, $f)
{
    $keyed = array();
    foreach (lc_lang_each($xs, $f) as $i => $v) {
        $k = lc_call($f, $v);
        $isNum = is_float($k) || is_int($k);
        $keyed[] = array($v, $isNum, $isNum ? (float) $k : 0.0, $isNum ? '' : lc_to_text($k), $i);
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
''';
