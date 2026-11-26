/// 规矩版本 2 的小库·PHP（`lc2.php`）。规矩见 docs/blocks-v5-parts/B-type-system.md 第 2、5、8、11 节；函数名和 Node 版一样（`Lc::名字`）。
///
/// 值在 PHP 里的样子：整数＝int；小数＝float；文字＝string（UTF-8）；是否＝bool；空＝null；列表＝LcList（里面一个数组；
/// PHP 的数组是“按值传”的，所以包一层）；字典＝LcDict（遍历按码点从小到大）；记录 / 变体 / 枚举 / 对象＝生成的 class
/// （分别继承 LcRec / LcVariant / LcEnum / LcObj）；函数＝Closure。“任意”里的数字一律是 float。
/// 只用 PHP 自带的 pcre、json，不要 mbstring。
library;

import 'package:lopicode/lang/rt2_php_host.dart';

/// 整份小库：这一份＋宿主那一半（rt2_php_host.dart）。
const String kRt2PhpSource = _core + kRt2PhpHost;

const String _core = r'''<?php
// LopiCode 积木的小库（PHP，严格规矩）。由 LopiCode 生成，别手改。
declare(strict_types=1);

// 抛出去的错：外面这层带着那句话；obj 是错误对象（小库自己报的错没有，接住的时候才按种类造）。
class LcError extends Exception { public ?object $obj = null; }
class LcRec {}
class LcVariant extends LcRec {}
class LcEnum { public function __construct(public string $name, public int $index) {} }
class LcObj {}
final class LcList { public function __construct(public array $a = []) {} }
final class LcDict { public function __construct(public array $a = []) {} }

final class Lc {
  const MAX = 9007199254740991;
  private static bool $wrote = false;
  private static $stdout = null;
  private static $stderr = null;

  static function fail(string $m): never { throw new LcError($m); }
  static function list(array $a): LcList { return new LcList($a); }
  static function dict(array $pairs): LcDict {
    $d = new LcDict();
    foreach ($pairs as $p) $d->a[$p[0]] = $p[1];
    return $d;
  }

  static function fmtNum(int|float $n): string {
    $n = (float)$n;
    if (is_nan($n)) return "不是数";
    if (is_infinite($n)) return $n > 0 ? "无穷大" : "-无穷大";
    if ($n == 0.0) return "0";
    if (floor($n) === $n && abs($n) <= self::MAX) return (string)(int)$n;
    preg_match('/^(-?)([0-9])(?:\.([0-9]+))?e([+-][0-9]+)$/', sprintf('%.11e', $n), $m);
    $digits = rtrim($m[2] . $m[3], "0");
    $e = (int)$m[4];
    $len = strlen($digits);
    if ($e >= 15 || $e < -7) return $m[1] . $digits[0] . ($len > 1 ? "." . substr($digits, 1) : "") . "e" . $e;
    if ($e >= $len - 1) return $m[1] . $digits . str_repeat("0", $e - $len + 1);
    if ($e >= 0) return $m[1] . substr($digits, 0, $e + 1) . "." . substr($digits, $e + 1);
    return $m[1] . "0." . str_repeat("0", -$e - 1) . $digits;
  }
  static function itext(int $n): string { return (string)$n; }
  static function boolText(bool $b): string { return $b ? "true" : "false"; }

  // —— 整数、小数 ——
  private static function chk(int|float $r): int {
    return is_int($r) && $r >= -self::MAX && $r <= self::MAX ? $r : self::fail("整数超出范围");
  }
  static function iadd(int $a, int $b): int { return self::chk($a + $b); }
  static function isub(int $a, int $b): int { return self::chk($a - $b); }
  static function imul(int $a, int $b): int { return self::chk($a * $b); }
  static function idiv(int $a, int $b): int { return $b === 0 ? self::fail("除以 0") : intdiv($a, $b); }
  static function imod(int $a, int $b): int { return $b === 0 ? self::fail("除以 0") : $a % $b; }
  static function fdiv(float $a, float $b): float { return $b == 0.0 ? self::fail("除以 0") : $a / $b; }
  static function fpow(float $a, float $b): float {
    if ($a == 0.0 && $b < 0) return INF;
    return pow($a, $b);
  }
  static function toInt(float $x): int {
    if (!is_finite($x) || abs($x) >= 9.3e18) self::fail("这个小数变不成整数：" . self::fmtNum($x));
    $t = (int)$x;
    return abs($t) <= self::MAX ? $t : self::fail("这个小数变不成整数：" . self::fmtNum($x));
  }
  static function floor(float $x): int { return self::toInt(is_finite($x) ? floor($x) : $x); }
  static function ceil(float $x): int { return self::toInt(is_finite($x) ? ceil($x) : $x); }
  static function round(float $x): int {
    if (!is_finite($x)) return self::toInt($x);
    $t = $x < 0 ? ceil($x) : floor($x);
    return self::toInt(abs($x - $t) >= 0.5 ? $t + ($x < 0 ? -1 : 1) : $t);
  }
  static function sqrt(float $x): float { return $x >= 0 ? sqrt($x) : NAN; }
  static function now(): float { return floor(microtime(true) * 1000); }
  static function steps(int $a, int $b, int $s): int {
    if ($s === 0 || ($b > $a && $s < 0) || ($b < $a && $s > 0)) return 0;
    return intdiv($b - $a, $s) + 1;
  }
  static function fsteps(float $a, float $b, float $s): int {
    if ($s == 0.0) return 0;
    $d = ($b - $a) / $s;
    if (!($d >= 0)) return 0;
    $n = floor($d + 1e-9) + 1;
    return $n >= self::MAX ? self::MAX : (int)$n;
  }

  // —— 文字（按码点） ——
  static function cps(string $s): array { return $s === "" ? [] : preg_split('//u', $s, -1, PREG_SPLIT_NO_EMPTY); }
  static function textLen(string $s): int { return count(self::cps($s)); }
  static function cmpText(string $a, string $b): int { return strcmp($a, $b) <=> 0; }
  private static function clamp(int $i, int $n): int { return $i < 0 ? 0 : ($i > $n ? $n : $i); }
  static function substring(string $s, int $from, int $to): string {
    $cs = self::cps($s);
    $a = self::clamp($from, count($cs));
    $b = self::clamp($to, count($cs));
    return $a >= $b ? "" : implode("", array_slice($cs, $a, $b - $a));
  }
  static function charAt(string $s, int $i): string {
    $cs = self::cps($s);
    return $i >= 0 && $i < count($cs) ? $cs[$i] : self::fail("位置 " . $i . " 超出了文字的范围（共 " . count($cs) . " 个字）");
  }
  private static function ord(string $c): int {
    $b = ord($c[0]);
    if ($b < 0x80) return $b;
    $n = $b >= 0xf0 ? 3 : ($b >= 0xe0 ? 2 : 1);
    $v = $b & (0x3f >> $n);
    for ($i = 1; $i <= $n; $i++) $v = ($v << 6) | (ord($c[$i]) & 0x3f);
    return $v;
  }
  static function codePoints(string $s): LcList { return new LcList(array_map(fn($c) => self::ord($c), self::cps($s))); }
  static function split(string $s, string $sep): LcList { return new LcList($sep === "" ? self::cps($s) : explode($sep, $s)); }
  static function startsWith(string $s, string $p): bool { return str_starts_with($s, $p); }
  static function endsWith(string $s, string $p): bool { return str_ends_with($s, $p); }
  static function contains(string $s, string $p): bool { return str_contains($s, $p); }
  static function indexOf(string $s, string $p): int {
    $at = strpos($s, $p);
    return $at === false ? -1 : self::textLen(substr($s, 0, $at));
  }
  static function replace(string $s, string $from, string $to): string { return $from === "" ? $s : str_replace($from, $to, $s); }
  static function trim(string $s): string {
    $ws = '[\t\n\x0b\f\r \x{a0}\x{1680}\x{2000}-\x{200a}\x{2028}\x{2029}\x{202f}\x{205f}\x{3000}\x{feff}]+';
    return preg_replace('/^' . $ws . '|' . $ws . '$/u', '', $s);
  }
  static function upper(string $s): string { return function_exists('mb_strtoupper') ? mb_strtoupper($s, 'UTF-8') : strtoupper($s); }
  static function lower(string $s): string { return function_exists('mb_strtolower') ? mb_strtolower($s, 'UTF-8') : strtolower($s); }
  static function repeatText(string $s, int $n): string { return $n <= 0 ? "" : str_repeat($s, $n); }
  static function parseInt(string $s): ?int {
    if (!preg_match('/^-?[0-9]+\z/', $s) || strlen($s) > 20) return null;
    $n = (float)$s;
    return abs($n) <= self::MAX ? (int)$s : null;
  }

  // —— 这个值是什么 ——
  static function isNum(mixed $x): bool { return is_int($x) || is_float($x); }
  static function kind(mixed $x): string {
    if ($x === null) return "空";
    if (is_bool($x)) return "是否";
    if (self::isNum($x)) return "数字";
    if (is_string($x)) return "文字";
    if ($x instanceof LcList) return "列表";
    if ($x instanceof LcDict) return "字典";
    if ($x instanceof Closure) return "函数";
    return "「" . self::nameOf($x) . "」";
  }
  private static function nameOf(object $x): string { return defined(get_class($x) . '::lcName') ? $x::lcName : "对象"; }
  private static function want(string $name, mixed $x): never { self::fail("这里要" . $name . "，拿到的是" . self::kind($x)); }
  static function asNum(mixed $x): float { return self::isNum($x) ? (float)$x : self::want("小数", $x); }
  static function asInt(mixed $x): int {
    if (!self::isNum($x)) self::want("整数", $x);
    if (is_float($x) && (!is_finite($x) || floor($x) !== $x) || abs($x) > self::MAX) self::fail("这里要整数，拿到的是 " . self::fmtNum($x));
    return (int)$x;
  }
  static function asText(mixed $x): string { return is_string($x) ? $x : self::want("文字", $x); }
  static function asBool(mixed $x): bool { return is_bool($x) ? $x : self::want("是否", $x); }
  static function asFn(mixed $x): Closure { return $x instanceof Closure ? $x : self::want("函数", $x); }
  static function asList(mixed $x): LcList { return $x instanceof LcList ? $x : self::want("列表", $x); }
  static function asDict(mixed $x): LcDict { return $x instanceof LcDict ? $x : self::want("字典", $x); }
  static function asOpt(mixed $x, Closure $f): mixed { return $x === null ? null : $f($x); }
  static function asA(mixed $x, string $type, string $name): object { return $x instanceof $type ? $x : self::want("「" . $name . "」", $x); }
  static function isKind(mixed $x, string $name): bool { return $x instanceof LcObj && in_array($name, $x::lcKinds, true); }
  static function asKind(mixed $x, string $name): object { return self::isKind($x, $name) ? $x : self::want("「" . $name . "」", $x); }
  static function widenOpt(int|float|null $x): ?float { return $x === null ? null : (float)$x; }
  private static function inside(string $where, Closure $f, mixed $v): mixed {
    try { return $f($v); } catch (LcError $e) { self::fail($where . "：" . $e->getMessage()); }
  }
  static function asListOf(mixed $x, Closure $f): LcList {
    $out = [];
    foreach (self::asList($x)->a as $i => $v) $out[] = self::inside("列表的位置 " . $i, $f, $v);
    return new LcList($out);
  }
  static function asDictOf(mixed $x, Closure $f): LcDict {
    $d = new LcDict();
    self::asDict($x);
    foreach (self::keys($x) as $k) $d->a[$k] = self::inside("字典的「" . $k . "」", $f, $x->a[$k]);
    return $d;
  }
  static function toDyn(mixed $x): mixed {
    if (is_int($x)) return (float)$x;
    if ($x instanceof LcList) return new LcList(array_map(fn($v) => self::toDyn($v), $x->a));
    if ($x instanceof LcDict) return new LcDict(array_map(fn($v) => self::toDyn($v), $x->a));
    return $x;
  }

  // —— 相等、比大小 ——
  static function eq(mixed $a, mixed $b): bool {
    if ($a === $b) return true;
    if ($a === null || $b === null) return false;
    if (self::isNum($a) && self::isNum($b)) return $a == $b;
    if ($a instanceof LcList) {
      if (!($b instanceof LcList) || count($a->a) !== count($b->a)) return false;
      foreach ($a->a as $i => $v) if (!self::eq($v, $b->a[$i])) return false;
      return true;
    }
    if ($a instanceof LcDict) {
      if (!($b instanceof LcDict) || count($a->a) !== count($b->a)) return false;
      foreach ($a->a as $k => $v) if (!array_key_exists($k, $b->a) || !self::eq($v, $b->a[$k])) return false;
      return true;
    }
    if ($a instanceof LcRec) {
      if (!($b instanceof LcRec) || get_class($a) !== get_class($b)) return false;
      $bv = get_object_vars($b);
      foreach (get_object_vars($a) as $k => $v) if (!self::eq($v, $bv[$k])) return false;
      return true;
    }
    return false;
  }
  static function cmp(mixed $a, mixed $b): int { return is_string($a) ? self::cmpText($a, $b) : $a <=> $b; }
  static function dcmp(mixed $a, mixed $b): int {
    if ((self::isNum($a) && self::isNum($b)) || (is_string($a) && is_string($b))) return self::cmp($a, $b);
    self::fail("比大小的两边要都是数字或者都是文字，拿到的是" . self::kind($a) . "和" . self::kind($b));
  }

  // —— 列表、字典 ——
  private static function outOf(int $i, int $n): never { self::fail("位置 " . $i . " 超出了列表的范围（共 " . $n . " 项）"); }
  static function at(LcList $xs, int $i): mixed { return $i >= 0 && $i < count($xs->a) ? $xs->a[$i] : self::outOf($i, count($xs->a)); }
  static function setAt(LcList $xs, int $i, mixed $v): void {
    if ($i >= 0 && $i < count($xs->a)) $xs->a[$i] = $v; else self::outOf($i, count($xs->a));
  }
  static function push(LcList $xs, mixed $v): void { $xs->a[] = $v; }
  static function pop(LcList $xs): mixed { return count($xs->a) > 0 ? array_pop($xs->a) : null; }
  static function len(LcList|LcDict $x): int { return count($x->a); }
  static function items(LcList $xs): array { return $xs->a; }
  static function keys(LcDict $d): array {
    $ks = array_map(fn($k) => (string)$k, array_keys($d->a));
    sort($ks, SORT_STRING);
    return $ks;
  }
  static function get(LcDict $d, string $k): mixed { return $d->a[$k] ?? null; }
  static function dictSet(LcDict $d, string $k, mixed $v): void { $d->a[$k] = $v; }
  static function dictRemove(LcDict $d, string $k): void { unset($d->a[$k]); }
  static function dictKeys(LcDict $d): LcList { return new LcList(self::keys($d)); }
  static function dictValues(LcDict $d): LcList { return new LcList(array_map(fn($k) => $d->a[$k], self::keys($d))); }
  static function dictHas(LcDict $d, string $k): bool { return array_key_exists($k, $d->a); }
  static function must(mixed $x): mixed { return $x === null ? self::fail("这里的值是空，不能直接用") : $x; }
  static function listMap(LcList $xs, Closure $f): LcList { return new LcList(array_map(fn($v) => $f($v), $xs->a)); }
  static function listFilter(LcList $xs, Closure $f): LcList { return new LcList(array_values(array_filter($xs->a, fn($v) => $f($v)))); }
  static function listReduce(LcList $xs, Closure $f, mixed $init): mixed {
    $acc = $init;
    foreach ($xs->a as $v) $acc = $f($acc, $v);
    return $acc;
  }
  static function listFind(LcList $xs, Closure $f): mixed {
    foreach ($xs->a as $v) if ($f($v)) return $v;
    return null;
  }
  static function listEvery(LcList $xs, Closure $f): bool {
    foreach ($xs->a as $v) if (!$f($v)) return false;
    return true;
  }
  static function listSome(LcList $xs, Closure $f): bool {
    foreach ($xs->a as $v) if ($f($v)) return true;
    return false;
  }
  static function listEach(LcList $xs, Closure $f): void { foreach ($xs->a as $v) $f($v); }
  static function listJoin(LcList $xs, string $sep): string { return implode($sep, $xs->a); }
  static function listReverse(LcList $xs): LcList { return new LcList(array_reverse($xs->a)); }
  static function listConcat(LcList $a, LcList $b): LcList { return new LcList(array_merge($a->a, $b->a)); }
  static function listSlice(LcList $xs, int $from, int $to): LcList {
    $a = self::clamp($from, count($xs->a));
    $b = self::clamp($to, count($xs->a));
    return new LcList($a >= $b ? [] : array_slice($xs->a, $a, $b - $a));
  }
  static function listIndexOf(LcList $xs, mixed $v): int {
    foreach ($xs->a as $i => $x) if (self::eq($x, $v)) return $i;
    return -1;
  }
  static function listContains(LcList $xs, mixed $v): bool { return self::listIndexOf($xs, $v) >= 0; }
  static function range(int $a, int $b): LcList { return new LcList($a <= $b ? range($a, $b) : []); }
  static function recCopy(object $r, array $changes): object {
    $o = clone $r;
    foreach ($changes as $k => $v) $o->$k = $v;
    return $o;
  }

  // —— “任意”的值之间（严格：不偷偷转换） ——
  private static function dnum(string $op, mixed $x): float { return self::isNum($x) ? (float)$x : self::fail($op . "的两边要数字，拿到的是" . self::kind($x)); }
  static function dadd(mixed $a, mixed $b): float { return self::dnum("加法", $a) + self::dnum("加法", $b); }
  static function dsub(mixed $a, mixed $b): float { return self::dnum("减法", $a) - self::dnum("减法", $b); }
  static function dmul(mixed $a, mixed $b): float { return self::dnum("乘法", $a) * self::dnum("乘法", $b); }
  static function ddiv(mixed $a, mixed $b): float { return self::fdiv(self::dnum("除法", $a), self::dnum("除法", $b)); }
  static function dpow(mixed $a, mixed $b): float { return self::fpow(self::dnum("乘方", $a), self::dnum("乘方", $b)); }
  static function didiv(mixed $a, mixed $b): float { return (float)self::idiv(self::asInt($a), self::asInt($b)); }
  static function dmod(mixed $a, mixed $b): float { return (float)self::imod(self::asInt($a), self::asInt($b)); }
  static function dynGet(mixed $x, mixed $k): mixed {
    if ($x instanceof LcList) return self::at($x, self::asInt($k));
    if ($x instanceof LcDict) return self::get($x, self::asText($k));
    self::fail("这里要列表或字典，拿到的是" . self::kind($x));
  }
  static function dynSet(mixed $x, mixed $k, mixed $v): void {
    if ($x instanceof LcList) { self::setAt($x, self::asInt($k), $v); return; }
    if ($x instanceof LcDict) { self::dictSet($x, self::asText($k), $v); return; }
    self::fail("这里要列表或字典，拿到的是" . self::kind($x));
  }
  static function dynPush(mixed $x, mixed $v): void { self::push(self::asList($x), $v); }
  static function dynPop(mixed $x): mixed { return self::pop(self::asList($x)); }
  static function dynRemove(mixed $x, mixed $k): void { self::dictRemove(self::asDict($x), self::asText($k)); }
  static function dynOrElse(mixed $x, mixed $d): mixed { return $x ?? $d; }
  static function dynSize(mixed $x): int {
    if (is_string($x)) return self::textLen($x);
    if ($x instanceof LcList || $x instanceof LcDict) return count($x->a);
    self::fail("这里要文字、列表或字典，拿到的是" . self::kind($x));
  }
  private static function jstr(string $s): string {
    $out = json_encode($s, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_LINE_TERMINATORS | JSON_INVALID_UTF8_SUBSTITUTE);
    return $out === false ? '""' : $out;
  }
  static function toJson(mixed $x): string {
    if ($x === null) return "null";
    if (is_bool($x)) return self::boolText($x);
    if (self::isNum($x)) return is_finite((float)$x) ? self::fmtNum($x) : "null";
    if (is_string($x)) return self::jstr($x);
    if ($x instanceof LcList) return "[" . implode(",", array_map(fn($v) => self::toJson($v), $x->a)) . "]";
    if ($x instanceof LcDict) return "{" . implode(",", array_map(fn($k) => self::jstr($k) . ":" . self::toJson($x->a[$k]), self::keys($x))) . "}";
    if ($x instanceof LcEnum) return self::jstr($x->name);
    if ($x instanceof LcRec) {
      $fs = get_object_vars($x);
      $ks = array_keys($fs);
      sort($ks, SORT_STRING);
      return "{" . implode(",", array_map(fn($k) => self::jstr(str_starts_with($k, "m_") ? substr($k, 2) : $k) . ":" . self::toJson($fs[$k]), $ks)) . "}";
    }
    return "null";
  }
  private static function fromDecoded(mixed $v): mixed {
    if (is_int($v)) return (float)$v;
    if (is_array($v)) return new LcList(array_map(fn($x) => self::fromDecoded($x), $v));
    if (is_object($v)) {
      $d = new LcDict();
      foreach (get_object_vars($v) as $k => $x) $d->a[(string)$k] = self::fromDecoded($x);
      return $d;
    }
    return $v;
  }
  static function fromJson(string $s): mixed {
    try {
      return self::fromDecoded(json_decode($s, false, 512, JSON_THROW_ON_ERROR));
    } catch (JsonException $e) {
      self::fail("这段文字不是 JSON");
    }
  }
  static function dtext(mixed $x): string {
    if ($x === null) return "";
    if (is_bool($x)) return self::boolText($x);
    if (self::isNum($x)) return self::fmtNum($x);
    if (is_string($x)) return $x;
    if ($x instanceof Closure) return "[函数]";
    if ($x instanceof LcEnum) return $x->name;
    if ($x instanceof LcList || $x instanceof LcDict || $x instanceof LcRec) return self::toJson($x);
    return "[" . self::nameOf($x) . "]";
  }

  // —— 输出：写一行就马上写出去（服务被关掉的时候不会丢）。用 php -S 开服务的时候没有 STDOUT 这个常量，自己开。——
  static function log(string $s): void {
    self::$stdout ??= defined('STDOUT') ? STDOUT : fopen('php://stdout', 'w');
    self::$wrote = true;
    fwrite(self::$stdout, $s . "\n");
    fflush(self::$stdout);
  }
  static function errLine(string $s): void {
    self::$stderr ??= defined('STDERR') ? STDERR : fopen('php://stderr', 'w');
    fwrite(self::$stderr, $s . "\n");
  }
  static function run(Closure $main): void {
    $failed = false;
    try { $main(); } catch (LcError $e) { self::log("出错：" . $e->getMessage()); $failed = true; }
    if (PHP_SAPI === 'cli-server') {
      // 一个请求把程序从头跑一遍：跑到这里还没有回应（没有调“开服务”，或者半路出错了）＝回 500。
      if (!headers_sent()) LcHost::hostError(500, "服务器内部出错");
      return;
    }
    if (!self::$wrote) fwrite(STDOUT, "\n"); // 什么都没写过的，补一个空行（和原来“攒到最后一次写”的样子一样）
    if ($failed) exit(1);
  }

  // —— 是不是数字、网址解码 ——
  static function isNumeric(mixed $x): bool {
    if (self::isNum($x)) return true;
    if (!is_string($x)) return false;
    $s = trim($x, " \t\n\r");
    return preg_match('/^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$/D', $s) === 1 && is_finite((float) $s);
  }
  static function toNumber(string $s): float {
    if (!self::isNumeric($s)) self::fail("「" . $s . "」变不成数字");
    return (float) trim($s, " \t\n\r");
  }
  // 这个值是不是某一类：null bool number text list dict function object。
  static function isType(mixed $x, string $name): bool {
    switch ($name) {
      case "null": return $x === null;
      case "bool": return is_bool($x);
      case "number": return self::isNum($x);
      case "text": return is_string($x);
      case "list": return $x instanceof LcList;
      case "dict": return $x instanceof LcDict;
      case "function": return $x instanceof Closure;
      case "object": return $x instanceof LcObj || $x instanceof LcRec || $x instanceof LcEnum;
    }
    self::fail("没有「" . $name . "」这一类值");
  }
  // 两个字典合成一个新的：后面的盖住前面的。
  static function dictMerge(LcDict $a, LcDict $b): LcDict {
    $d = new LcDict($a->a);
    foreach ($b->a as $k => $v) $d->a[$k] = $v;
    return $d;
  }
  static function urlDecode(string $s): string {
    if (preg_match('/%(?![0-9A-Fa-f]{2})/', $s) === 1) self::fail("这段网址编码解不开");
    $r = rawurldecode($s);
    if (preg_match('//u', $r) !== 1) self::fail("这段网址编码解不开");
    return $r;
  }

  // —— 宿主（清单见 host_v2.dart；格子、要等的事、开服务在下面的 LcHost 里）——
  static function hostPrint(string $s, string $ch): void {
    if ($ch === "out") self::log($s);
    elseif ($ch === "err") self::errLine($s);
    else self::fail("通道只能是 out 或 err");
  }
  static function hostNow(): int { return (int) floor(microtime(true) * 1000); }
  static function copyVal(mixed $v): mixed {
    if ($v instanceof LcList) return new LcList(array_map(fn($x) => self::copyVal($x), $v->a));
    if ($v instanceof LcDict) {
      $d = new LcDict();
      foreach ($v->a as $k => $x) $d->a[$k] = self::copyVal($x);
      return $d;
    }
    return $v;
  }

  // —— 错误对象 ——
  private const ERR_KINDS = [["除以 0", "数值不对"], ["整数超出范围", "数值不对"], ["变不成整数", "数值不对"], ["超出了", "找不到"], ["拿到的是", "类型不对"], ["值是空", "类型不对"]];
  private static ?Closure $errMake = null;
  static function errKind(string $m): string {
    foreach (self::ERR_KINDS as [$part, $k]) { if (str_contains($m, $part)) return $k; }
    return "错误";
  }
  static function errSetup(Closure $f): void { self::$errMake = $f; }
  static function errOf(string $m, object $obj): LcError { $e = new LcError($m); $e->obj = $obj; return $e; }
  static function errObj(LcError $e): object {
    if ($e->obj === null) $e->obj = (self::$errMake)(self::errKind($e->getMessage()), $e->getMessage());
    return $e->obj;
  }
  static function kindOf(object $x): string { return $x::lcName;
  }
}
''';
