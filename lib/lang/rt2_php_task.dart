/// 规矩版本 2 的小库·PHP·“要等的事”那一块（拼在 `lc2.php` 里，见 rt2_php_host.dart）。
///
/// PHP 里没有“同时做”：“开始做”就是当场把那件事从头做到尾，做完才回来。所以别的语言里靠“两件事同时在跑”才有的东西，
/// PHP 只能**按“假如它们是同时做的”把时间算出来**（细则和它跟别的语言不一样的地方见 docs/blocks-v5-parts/B-gen-notes.md 第 16.6 节）：
/// - 每件事记着“我做到第几毫秒了”（[LcLine.now]）：等一会儿、请求网址花掉的时间往上加；别的计算不算时间。
///   “开始做”的那件事从开始它的人当时的毫秒数起算，做完时的毫秒数记在结果上（[LcTask.at]）。
/// - 等：把自己的毫秒数拨到那件事做完的时候（已经过了就不动）。
/// - 等，最多 N 毫秒：那件事做完的时候比“现在＋N”还晚＝抛“超时”（自己的毫秒数加 N）。**真的时间一点没省**——那件事早就当场做完了。
/// - 取消：那件事按算出来的时间“这会儿还没做完”＝把它记成“被取消了”，以后等它拿到的是“取消了”错误、拿不到它的结果。
///   **它做过的事（打印、改格子、写文件、发请求）都已经发生了，收不回来**；它自己里面也看不到“被取消了”。
/// - 一次只让一个做：一个请求里本来就是一件一件做的；开了服务（php -S）时用带锁的文件，几个工作进程之间真的排队。
library;

const String kRt2PhpTask = r'''
// “开始做”的结果：PHP 里已经做完了，值或者错记在里面。at＝按“假如是同时做的”算，它做完的时候是第几毫秒。
final class LcTask {
  public bool $cancelled = false;
  public function __construct(public mixed $val, public ?LcError $err, public int $at) {}
}
// 一件事（主程序 / 这个请求、一次“开始做”）：now＝它做到第几毫秒了。
final class LcLine { public int $now = 0; }

final class LcWait {
  private static array $lines = [];
  private static array $gates = []; // 名字 => [哪条线拿着, 锁文件（没开服务时是 null）]

  private static function line(): LcLine {
    if (count(self::$lines) === 0) self::$lines[] = new LcLine();
    return self::$lines[count(self::$lines) - 1];
  }
  static function spent(int $ms): void { if ($ms > 0) self::line()->now += $ms; }
  static function sleep(int $ms): void {
    if ($ms <= 0) return;
    usleep($ms * 1000);
    self::line()->now += $ms;
  }
  static function spawn(Closure $f): LcTask {
    $child = new LcLine();
    $child->now = self::line()->now;
    self::$lines[] = $child;
    try {
      try { $t = new LcTask($f(), null, 0); } catch (LcError $e) { $t = new LcTask(null, $e, 0); }
    } finally { array_pop(self::$lines); }
    $t->at = $child->now;
    return $t;
  }
  private static function get(LcTask $t): mixed {
    if ($t->cancelled) Lc::fail("这件事被取消了");
    if ($t->err !== null) throw $t->err;
    return $t->val;
  }
  private static function reach(int $at): void { $me = self::line(); if ($at > $me->now) $me->now = $at; }
  static function wait(LcTask $t): mixed {
    self::reach($t->at);
    return self::get($t);
  }
  static function awaitMax(LcTask $t, int $ms): mixed {
    $ms = max(0, $ms);
    $me = self::line();
    if ($t->at > $me->now + $ms) {
      $me->now += $ms;
      Lc::fail("等了 " . $ms . " 毫秒还没做完");
    }
    return self::wait($t);
  }
  // 按算出来的时间这会儿还没做完的，记成“被取消了”（它做过的事收不回来）。
  static function cancel(LcTask $t): void {
    $now = self::line()->now;
    if ($t->at > $now) { $t->cancelled = true; $t->at = $now; }
  }
  private static function failed(LcTask $t): bool { return $t->cancelled || $t->err !== null; }
  static function awaitAll(LcList $list): LcList {
    $ts = $list->a;
    $bad = null;
    foreach ($ts as $t) if (self::failed($t) && ($bad === null || $t->at < $bad->at)) $bad = $t;
    if ($bad !== null) {
      self::reach($bad->at);
      foreach ($ts as $t) if ($t !== $bad) self::cancel($t);
      return self::get($bad);
    }
    $out = [];
    foreach ($ts as $t) { self::reach($t->at); $out[] = $t->val; }
    return new LcList($out);
  }
  static function awaitAny(LcList $list): mixed {
    $ts = $list->a;
    if (count($ts) === 0) Lc::fail("“等最先的一个”的列表是空的");
    $first = $ts[0];
    foreach ($ts as $t) if ($t->at < $first->at) $first = $t;
    self::reach($first->at);
    return self::get($first);
  }
  // 一次只让一个做。$store＝开了服务时格子文件的路径（锁文件放它旁边），没开服务是 null。
  static function lockEnter(string $name, ?string $store): string {
    $me = self::line();
    if (isset(self::$gates[$name])) {
      if (self::$gates[$name][0] === $me) Lc::fail("「" . $name . "」已经在“一次只让一个做”里面了，不能在里面再进一次");
      // 拿着它的是开始这件事的那一边：别的语言里这里会排队等它出来；PHP 里它要等这件事做完才能接着走，永远等不到。
      Lc::fail("「" . $name . "」正被开始这件事的那一边占着：PHP 里“开始做”是当场做完的，等不到它出来");
    }
    $h = null;
    if ($store !== null) {
      $h = fopen(preg_replace('/\.dat\z/', '-' . md5($name) . '.gate', $store), 'c');
      if ($h === false) Lc::fail("“一次只让一个做”用不了：锁文件开不了");
      flock($h, LOCK_EX); // 别的工作进程在里面＝排队
    }
    self::$gates[$name] = [$me, $h];
    return $name;
  }
  static function lockLeave(string $name): void {
    $g = self::$gates[$name] ?? null;
    if ($g === null || $g[0] !== self::line()) return;
    unset(self::$gates[$name]);
    if ($g[1] !== null) { flock($g[1], LOCK_UN); fclose($g[1]); }
  }
}

''';
