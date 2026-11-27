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
    // 开了几个工作进程（PHP_CLI_SERVER_WORKERS）时每个请求落在不同的进程上：格子要认“最上面那个服务进程”，不然各存各的。
    // 顺着父进程往上找命令行和自己一样的（就是 php -S 起的那一个）；没有 /proc 的系统只认自己。
    $pid = getmypid();
    $fields = function ($p) {
      $stat = @file_get_contents('/proc/' . $p . '/stat');
      return is_string($stat) && strrpos($stat, ')') !== false ? explode(' ', substr($stat, strrpos($stat, ')') + 2)) : [];
    };
    $me = @file_get_contents('/proc/' . $pid . '/cmdline');
    for ($i = 0; $i < 3 && is_string($me) && $me !== ''; $i++) {
      $up = (int)($fields($pid)[1] ?? 0);
      if ($up <= 1 || @file_get_contents('/proc/' . $up . '/cmdline') !== $me) break;
      $pid = $up;
    }
    $start = $fields($pid)[19] ?? '';
    $dir = sys_get_temp_dir();
    self::$path = $dir . '/lcstore-' . $pid . '-' . $start . '.dat';
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
  // —— 随机字节、文件、请求别的网址（细则见 docs/blocks-v5-parts/B-gen-notes.md 第 14 节）——
  static function hostRandomBytes(int $n): LcList {
    if ($n < 1 || $n > 1024) Lc::fail("随机字节的个数要在 1 到 1024 之间");
    return new LcList(array_values(unpack('C*', random_bytes($n))));
  }
  private static function filePath(string $p): string {
    if ($p === "" || $p[0] === "/" || $p[0] === "\\" || preg_match('/\A[A-Za-z]:/', $p) || in_array("..", preg_split('/[\/\\\\]/', $p), true)) {
      Lc::fail("路径不对：只能用工程文件夹里面的相对路径");
    }
    return getcwd() . "/" . $p;
  }
  static function fileRead(string $p): string {
    $full = self::filePath($p);
    if (!file_exists($full)) Lc::fail("读不了文件：没有「" . $p . "」");
    $raw = is_file($full) ? @file_get_contents($full) : false;
    if ($raw === false) Lc::fail("读不了文件：「" . $p . "」");
    if (preg_match('//u', $raw) !== 1) Lc::fail("读不了文件：「" . $p . "」不是 UTF-8 文字");
    return $raw;
  }
  static function fileWrite(string $p, string $text): void {
    $full = self::filePath($p);
    $tmp = $full . ".lctmp" . getmypid();
    $dir = dirname($full);
    $ok = (is_dir($dir) || @mkdir($dir, 0777, true)) && @file_put_contents($tmp, $text) !== false && @rename($tmp, $full);
    if (!$ok) {
      @unlink($tmp);
      Lc::fail("写不了文件：「" . $p . "」");
    }
  }
  static function fileExists(string $p): bool { return file_exists(self::filePath($p)); }
  static function fileList(string $p): LcList {
    $full = self::filePath($p);
    $names = is_dir($full) ? @scandir($full) : false;
    if ($names === false) Lc::fail("列不了文件夹：「" . $p . "」");
    $names = array_values(array_filter($names, fn($n) => $n !== "." && $n !== ".."));
    sort($names, SORT_STRING);
    return new LcList($names);
  }
  static function fileRemove(string $p): void {
    $full = self::filePath($p);
    if (!is_file($full) || !@unlink($full)) Lc::fail("删不了文件：「" . $p . "」");
  }
  // 网址里的空格、中文、写法不对的百分号先按 UTF-8 做百分号转义（各语言自己的处理不一样，这里统一）；# 后面的不发。
  private static function encodeUrl(string $s): string {
    $hash = strpos($s, '#');
    if ($hash !== false) $s = substr($s, 0, $hash);
    return preg_replace_callback('/%(?![0-9A-Fa-f]{2})|[^A-Za-z0-9\-._~:\/?\[\]@!$&\'()*+,;=%]/', fn($m) => sprintf('%%%02X', ord($m[0])), $s);
  }
  // 把字节读成文字，坏的地方换成 U+FFFD（换法和浏览器的标准一致：一段读不下去的开头算一个）。
  private static function decodeUtf8(string $raw): string {
    if (preg_match('//u', $raw) === 1) return $raw;
    $good = '[\x00-\x7F]|[\xC2-\xDF][\x80-\xBF]|\xE0[\xA0-\xBF][\x80-\xBF]|[\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}|\xED[\x80-\x9F][\x80-\xBF]'
      . '|\xF0[\x90-\xBF][\x80-\xBF]{2}|[\xF1-\xF3][\x80-\xBF]{3}|\xF4[\x80-\x8F][\x80-\xBF]{2}';
    $cut = '\xE0[\xA0-\xBF]|[\xE1-\xEC\xEE\xEF][\x80-\xBF]|\xED[\x80-\x9F]|\xF0[\x90-\xBF][\x80-\xBF]?|[\xF1-\xF3][\x80-\xBF]{1,2}|\xF4[\x80-\x8F][\x80-\xBF]?';
    return preg_replace_callback('/((?:' . $good . ')+)|' . $cut . '|[\x80-\xFF]/', fn($m) => isset($m[1]) && $m[1] !== '' ? $m[1] : "\xEF\xBF\xBD", $raw);
  }
  static function hostFetch(string $method, string $url, LcDict $headers, ?string $body, int $timeoutMs): LcDict {
    if (!preg_match('/\Ahttps?:\/\//i', $url)) Lc::fail("请求不了：网址要以 http:// 或 https:// 开头");
    if (!in_array($method, ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"], true)) Lc::fail("请求不了：不认识的方式「" . $method . "」");
    if ($timeoutMs <= 0) Lc::fail("请求不了：超时毫秒要大于 0");
    $lines = "Connection: close\r\n";
    $hasType = false; $hasAgent = false;
    foreach (Lc::keys($headers) as $k) {
      $low = strtolower($k);
      if (in_array($low, ["host", "content-length", "connection", "expect", "upgrade"], true)) continue;
      $hasType = $hasType || $low === "content-type";
      $hasAgent = $hasAgent || $low === "user-agent";
      $lines .= $k . ": " . $headers->a[$k] . "\r\n";
    }
    if (!$hasAgent) $lines .= "User-Agent: LopiCode\r\n";
    $http = ['method' => $method, 'timeout' => $timeoutMs / 1000, 'ignore_errors' => true, 'follow_location' => 1, 'protocol_version' => 1.1];
    if ($body !== null && $method !== "GET" && $method !== "HEAD") {
      $http['content'] = $body;
      if (!$hasType) $lines .= "Content-Type: text/plain; charset=utf-8\r\n";
    }
    $http['header'] = $lines;
    $began = microtime(true);
    $fp = @fopen(self::encodeUrl($url), 'r', false, stream_context_create(['http' => $http]));
    $raw = $fp === false ? false : stream_get_contents($fp);
    $meta = $fp === false ? [] : stream_get_meta_data($fp);
    if ($fp !== false) fclose($fp);
    $late = (microtime(true) - $began) * 1000 >= $timeoutMs * 0.9;
    if ($raw === false || ($meta['timed_out'] ?? false)) Lc::fail(($meta['timed_out'] ?? false) || $late ? "请求超时了" : "请求不了：连不上");
    $status = 0;
    $back = new LcDict();
    foreach (($meta['wrapper_data'] ?? []) as $line) {
      $line = (string) $line;
      // 跟着跳转时会有好几段回应头，最后一段才是最终的
      if (preg_match('/\AHTTP\/[0-9.]+\s+([0-9]{3})/', $line, $m)) { $status = (int) $m[1]; $back = new LcDict(); continue; }
      $c = strpos($line, ':');
      if ($c === false) continue;
      $name = strtolower(trim(substr($line, 0, $c)));
      $value = trim(substr($line, $c + 1));
      $back->a[$name] = array_key_exists($name, $back->a) ? $back->a[$name] . ", " . $value : $value;
    }
    if ($status === 0) Lc::fail("请求不了：连不上");
    return new LcDict(["status" => (float) $status, "headers" => $back, "body" => self::decodeUtf8($raw)]);
  }
}
''';
