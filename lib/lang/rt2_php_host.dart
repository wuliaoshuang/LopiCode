/// 规矩版本 2 的小库·PHP·宿主那一半（接在 rt2_php.dart 后面，同一个 `lc2.php`）：格子、要等的事、开服务。
///
/// PHP 一个请求把程序从头跑一遍（`php -S 主机:端口 main.php`），所以：
/// - 格子：直接跑（`php main.php`）的时候在内存里；开服务的时候放在带锁的文件里（请求之间才留得住）。
/// - 要等的事：没有“同时做”——“开始做”就是马上做完，“等”就是把结果拿出来；“等一会儿”停的就是这个请求。
/// - 开服务：跑到“开服务”这一句，就处理眼前这一个请求，回完就结束。
/// 细则见 docs/blocks-v5-parts/C-library-system.md 9.1 和 B-gen-notes.md 第 12 节。
library;

const String kRt2PhpHost = r'''
// “开始做”的结果：PHP 里已经做完了，值或者错记在里面。
final class LcTask { public function __construct(public mixed $val, public ?LcError $err) {} }

final class LcHost {
  const BODY_LIMIT = 1048576;

  static function hostPrint(string $s, string $ch): void { Lc::hostPrint($s, $ch); }
  static function hostNow(): int { return Lc::hostNow(); }
  static function hostEnv(string $name): ?string { $v = getenv($name); return $v === false ? null : $v; }
  static function hostSleep(int $ms): void { if ($ms > 0) usleep($ms * 1000); }
  static function spawn(Closure $f): LcTask {
    try { return new LcTask($f(), null); } catch (LcError $e) { return new LcTask(null, $e); }
  }
  static function wait(LcTask $t): mixed {
    if ($t->err !== null) throw $t->err;
    return $t->val;
  }

  // —— 格子 ——
  private static array $mem = [];
  private static array $busy = [];
  private static ?array $tx = null; // 正在改的时候：整个文件的内容（拿着锁）
  private static ?string $path = null;

  // 开服务的时候格子放在哪个文件：名字里带服务进程的编号和它开始的时刻，所以重新开服务是新的格子。
  private static function file(): ?string {
    if (PHP_SAPI !== 'cli-server') return null;
    if (self::$path !== null) return self::$path;
    $start = '';
    $stat = @file_get_contents('/proc/self/stat');
    if (is_string($stat) && strrpos($stat, ')') !== false) $start = explode(' ', substr($stat, strrpos($stat, ')') + 2))[19] ?? '';
    $dir = sys_get_temp_dir();
    self::$path = $dir . '/lcstore-' . getmypid() . '-' . $start . '.dat';
    if (!file_exists(self::$path) && is_dir('/proc')) {
      // 顺手清掉已经不在了的服务留下的格子文件。
      foreach (glob($dir . '/lcstore-*.dat') ?: [] as $old) {
        if (preg_match('/lcstore-([0-9]+)-/', $old, $m) === 1 && !is_dir('/proc/' . $m[1])) @unlink($old);
      }
    }
    return self::$path;
  }
  private static function load($h): array {
    rewind($h);
    $raw = stream_get_contents($h);
    $all = is_string($raw) && $raw !== '' ? @unserialize($raw) : [];
    return is_array($all) ? $all : [];
  }
  static function storeRead(string $name): mixed {
    $path = self::file();
    if ($path === null) return array_key_exists($name, self::$mem) ? Lc::copyVal(self::$mem[$name]) : null;
    if (self::$tx !== null) return Lc::copyVal(self::$tx[$name] ?? null);
    $h = fopen($path, 'c+');
    if ($h === false) Lc::fail("格子读不了");
    flock($h, LOCK_SH);
    try { return self::load($h)[$name] ?? null; } finally { flock($h, LOCK_UN); fclose($h); }
  }
  static function storeUpdate(string $name, Closure $f): mixed {
    if (isset(self::$busy[$name])) Lc::fail("「" . $name . "」这个格子正在改，不能在改它的函数里再改它");
    self::$busy[$name] = true;
    try {
      $path = self::file();
      if ($path === null) {
        $v = Lc::copyVal($f(self::storeRead($name)));
        self::$mem[$name] = $v;
        return Lc::copyVal($v);
      }
      if (self::$tx !== null) { // 改这个格子的函数里又改另一个格子：锁已经拿着了
        $v = Lc::copyVal($f(self::storeRead($name)));
        self::$tx[$name] = $v;
        return Lc::copyVal($v);
      }
      $h = fopen($path, 'c+');
      if ($h === false) Lc::fail("格子改不了");
      flock($h, LOCK_EX); // 别的请求同时改＝排队
      try {
        self::$tx = self::load($h);
        $v = Lc::copyVal($f(self::storeRead($name)));
        self::$tx[$name] = $v;
        ftruncate($h, 0);
        rewind($h);
        fwrite($h, serialize(self::$tx));
        fflush($h);
        return Lc::copyVal($v);
      } finally { self::$tx = null; flock($h, LOCK_UN); fclose($h); }
    } finally { unset(self::$busy[$name]); }
  }

  // —— 开服务 ——
  private static function write(int $status, LcDict $headers, string $text): void {
    $noBody = $status === 204 || $status === 304 || $status < 200;
    header_remove();
    http_response_code($status);
    foreach (Lc::keys($headers) as $k) {
      if (strtolower($k) !== 'content-length') header($k . ': ' . Lc::dtext($headers->a[$k]));
    }
    if (!$noBody) header('Content-Length: ' . strlen($text));
    if (!$noBody && ($_SERVER['REQUEST_METHOD'] ?? '') !== 'HEAD') echo $text;
  }
  static function hostError(int $status, string $message): void {
    self::write($status, Lc::dict([["Content-Type", "application/json; charset=utf-8"]]), Lc::toJson(Lc::dict([["error", $message]])));
  }
  // 处理眼前这一个请求，回完就结束（不返回）。
  static function hostServe(int $port, string $host, Closure $handler): never {
    if (PHP_SAPI !== 'cli-server') Lc::fail("开不了服务：PHP 里要这样启动——php -S 主机:端口 main.php");
    ini_set('default_mimetype', '');
    if ((int) ($_SERVER['CONTENT_LENGTH'] ?? 0) > self::BODY_LIMIT) { self::hostError(413, "请求内容太大"); exit(0); }
    $raw = file_get_contents('php://input');
    $body = is_string($raw) && preg_match('//u', $raw) === 1 ? $raw : null;
    $headers = new LcDict();
    foreach (getallheaders() as $name => $value) {
      $name = strtolower((string) $name);
      $value = trim((string) $value, " \t");
      $headers->a[$name] = array_key_exists($name, $headers->a) ? $headers->a[$name] . ", " . $value : $value;
    }
    $uri = (string) ($_SERVER['REQUEST_URI'] ?? '/');
    $q = strpos($uri, '?');
    $request = Lc::dict([
      ["method", (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET')], ["path", $q === false ? $uri : substr($uri, 0, $q)],
      ["query", $q === false ? "" : substr($uri, $q + 1)], ["headers", $headers], ["body", $body],
    ]);
    try { $out = $handler($request); } catch (LcError $e) {
      Lc::errLine("出错：" . $e->getMessage());
      self::hostError(500, "服务器内部出错");
      exit(0);
    }
    $status = $out instanceof LcDict ? ($out->a["status"] ?? null) : null;
    if (is_float($status) && $status == floor($status)) $status = (int) $status;
    if (!is_int($status) || $status < 100 || $status > 599) {
      Lc::errLine("处理函数返回的响应不对（要一个字典，status 是 100 到 599 的整数）");
      self::hostError(500, "服务器内部出错");
      exit(0);
    }
    $hs = $out->a["headers"] ?? null;
    self::write($status, $hs instanceof LcDict ? $hs : new LcDict(), Lc::dtext($out->a["body"] ?? null));
    exit(0);
  }
}
''';
