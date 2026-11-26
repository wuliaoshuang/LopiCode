/// PHP 运行时小库的源码（读请求、写响应、请求别的网址、路由；生成的工程里的 `lc_server.php`）。每份工程都一样。
///
/// 2026-11-26 起在开发机上用 PHP 8.3 真跑（test/backend_conformance_test.dart，和别的语言同一份样本）；手机上的 PHP 没验证过。用到的 PHP 函数清单见 docs/api-notes.md。
/// 值的规矩见 backend_ir.dart 的 `kBeRuntimeFns`，改这里的行为要同时改别的语言的小库。
library;

const String kPhpRuntimeServerSource = r'''
<?php
// LopiCode 后端运行时小库（PHP）：读请求、写响应、请求别的网址、路由。每份生成的工程都一样，不用改。
// 用 PHP 自带的开发服务器跑：php -S 0.0.0.0:端口 server.php ——每来一个请求，server.php 从头跑一遍。
// 这份代码在电脑上用 PHP 8.3 跑通过一致性测试。

// 报错（警告、提示）不许混进响应里：PHP 默认会把它们当网页内容输出，响应就坏了。改成只写到服务的终端（标准错误）。
ini_set('display_errors', '0');
ini_set('log_errors', '1');

// 这次请求。
final class LcRequest
{
    public $params = array(); // 路径参数
    public $rawQuery = '';
    public $query = null; // 第一次用到时才解析
    public $headers = array(); // 名字（原样大小写）→ 值
    public $rawBody = '';
    public $parsed = false;
    public $body = null;
}

// —— 请求 ——

// 百分号解码；写法不对（%zz、解出来不是合法 UTF-8）就原样返回。
function lc_pct($s)
{
    if (strpos($s, '%') === false || preg_match('/%(?![0-9A-Fa-f]{2})/', $s)) {
        return $s;
    }
    $out = rawurldecode($s);
    return lc_is_utf8($out) ? $out : $s;
}

function lc_parse_query($raw)
{
    $out = array();
    foreach (explode('&', $raw) as $part) {
        if ($part === '') {
            continue;
        }
        $i = strpos($part, '=');
        $key = lc_pct(str_replace('+', ' ', $i === false ? $part : substr($part, 0, $i)));
        $value = $i === false ? '' : lc_pct(str_replace('+', ' ', substr($part, $i + 1)));
        if (!array_key_exists($key, $out)) {
            $out[$key] = $value; // 重名取第一个
        }
    }
    return $out;
}

function lc_pathParam($req, $name)
{
    return array_key_exists((string) $name, $req->params) ? $req->params[(string) $name] : null;
}

function lc_query($req, $name)
{
    if ($req->query === null) {
        $req->query = lc_parse_query($req->rawQuery);
    }
    return array_key_exists((string) $name, $req->query) ? $req->query[(string) $name] : null;
}

function lc_body($req)
{
    if (!$req->parsed) {
        $req->parsed = true;
        $req->body = lc_parse_json($req->rawBody);
    }
    return $req->body;
}

function lc_bodyField($req, $name)
{
    return lc_field(lc_body($req), $name);
}

// 请求头的值（名字不分大小写；值去掉两头的空格 / 制表）。
function lc_header($req, $name)
{
    $want = strtolower((string) $name);
    foreach ($req->headers as $k => $v) {
        if (strtolower((string) $k) === $want) {
            return trim((string) $v, " \t");
        }
    }
    return null;
}

// 从 PHP 给的环境里把请求头找出来。
function lc_read_headers()
{
    if (function_exists('getallheaders')) {
        $all = getallheaders();
        if (is_array($all)) {
            return $all;
        }
    }
    // 退路：$_SERVER 里的 HTTP_X_TEST 这种写法（名字里的 - 变成了 _）
    $out = array();
    foreach ($_SERVER as $k => $v) {
        if (is_string($k) && strncmp($k, 'HTTP_', 5) === 0 && is_string($v)) {
            $out[str_replace('_', '-', substr($k, 5))] = $v;
        }
    }
    return $out;
}

// —— 响应 ——

function lc_status_of($v)
{
    $n = lc_to_num($v);
    return $n >= 200 && $n < 600 ? (int) $n : 200;
}

function lc_sendJson($status, $value)
{
    return array('status' => lc_status_of($status), 'type' => 'application/json; charset=utf-8', 'body' => lc_to_json($value));
}

function lc_sendText($status, $value)
{
    return array('status' => lc_status_of($status), 'type' => 'text/plain; charset=utf-8', 'body' => lc_to_text($value));
}

function lc_error($status, $message)
{
    return lc_sendJson($status, lc_obj('error', $message));
}

// 把响应发出去。$extra 是另外要带的响应头。
function lc_write($out, $extra = array())
{
    header_remove('X-Powered-By');
    http_response_code($out['status']);
    header('Access-Control-Allow-Origin: *');
    foreach ($extra as $line) {
        header($line);
    }
    if ($out['status'] === 204 || $out['status'] === 304) {
        return; // 不带内容，也不带 Content-Type
    }
    header('Content-Type: ' . $out['type']);
    header('Content-Length: ' . strlen($out['body']));
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'HEAD') {
        echo $out['body'];
    }
}

// —— 请求别的网址 ——

// 网址里的空格、中文、写法不对的百分号先按 UTF-8 做百分号转义（各语言自己的处理不一样，这里统一）。
// 字母、数字和 -._~:/?#[]@!$&'()*+,;= 原样；后面跟着两位十六进制的 % 原样；其余每个字节写成 %XX（大写）。
function lc_encode_url($s)
{
    return preg_replace_callback(
        '/%(?![0-9A-Fa-f]{2})|[^A-Za-z0-9\-._~:\/?#\[\]@!$&\'()*+,;=%]/',
        function ($m) {
            return sprintf('%%%02X', ord($m[0]));
        },
        $s
    );
}

// 把字节读成文字，坏的地方换成 U+FFFD（换法和浏览器的标准一致：一段读不下去的开头算一个）。
function lc_decode_utf8($raw)
{
    if (lc_is_utf8($raw)) {
        return $raw;
    }
    $good = '[\x00-\x7F]|[\xC2-\xDF][\x80-\xBF]|\xE0[\xA0-\xBF][\x80-\xBF]|[\xE1-\xEC\xEE\xEF][\x80-\xBF]{2}|\xED[\x80-\x9F][\x80-\xBF]'
        . '|\xF0[\x90-\xBF][\x80-\xBF]{2}|[\xF1-\xF3][\x80-\xBF]{3}|\xF4[\x80-\x8F][\x80-\xBF]{2}';
    $cut = '\xE0[\xA0-\xBF]|[\xE1-\xEC\xEE\xEF][\x80-\xBF]|\xED[\x80-\x9F]|\xF0[\x90-\xBF][\x80-\xBF]?|[\xF1-\xF3][\x80-\xBF]{1,2}|\xF4[\x80-\x8F][\x80-\xBF]?';
    return preg_replace_callback(
        '/((?:' . $good . ')+)|' . $cut . '|[\x80-\xFF]/',
        function ($m) {
            return isset($m[1]) && $m[1] !== '' ? $m[1] : "\xEF\xBF\xBD";
        },
        $raw
    );
}

// 成功（2xx）返回响应的文字；失败、超时、不是 http(s) 网址、网址里带用户名密码一律返回 null。
function lc_fetch($method, $url, $data)
{
    $target = lc_to_text($url);
    if (!preg_match('/\Ahttps?:\/\//i', $target)) {
        return null;
    }
    // 主机那一段带 @（用户名密码）的不请求
    if (preg_match('/\A[^\/?#]*@/', substr($target, strpos($target, '://') + 3))) {
        return null;
    }
    $hash = strpos($target, '#');
    if ($hash !== false) {
        $target = substr($target, 0, $hash); // # 后面的不发给对方
    }
    $target = lc_encode_url($target);
    $http = array('method' => $method === 'POST' ? 'POST' : 'GET', 'timeout' => LC_FETCH_TIMEOUT, 'ignore_errors' => true, 'header' => "Connection: close\r\n");
    if ($http['method'] === 'POST' && $data !== null) {
        $http['content'] = lc_to_json($data);
        $http['header'] .= "Content-Type: application/json; charset=utf-8\r\n";
    }
    $text = @file_get_contents($target, false, stream_context_create(array('http' => $http)));
    if ($text === false) {
        return null;
    }
    // 响应头：PHP 8.4 起用函数取，之前是一个自动出现的变量
    $lines = function_exists('http_get_last_response_headers') ? http_get_last_response_headers() : (isset($http_response_header) ? $http_response_header : null);
    $status = 0;
    if (!is_array($lines)) {
        $lines = array();
    }
    foreach ($lines as $line) {
        // 跟着跳转时会有好几行状态，最后一行才是最终的
        if (preg_match('/\AHTTP\/[0-9.]+\s+([0-9]{3})/', (string) $line, $m)) {
            $status = (int) $m[1];
        }
    }
    if ($status < 200 || $status > 299) {
        return null;
    }
    $text = lc_decode_utf8($text);
    // 开头的 BOM（U+FEFF）去掉一个
    return strncmp($text, "\xEF\xBB\xBF", 3) === 0 ? substr($text, 3) : $text;
}

// —— 路由 ——

final class LcRoutes
{
    public static $list = array();
}

// 登记一个接口。path 里的 :名字 是路径参数；$handler 是函数的名字。
function lc_route($method, $path, $handler)
{
    LcRoutes::$list[] = array('method' => $method, 'segments' => lc_segments($path), 'handler' => $handler);
}

// 按 / 切段，空段不要。
function lc_segments($path)
{
    $out = array();
    foreach (explode('/', $path) as $s) {
        if ($s !== '') {
            $out[] = $s;
        }
    }
    return $out;
}

// 路径对得上就返回参数表，否则 null。
function lc_match($pattern, $segments)
{
    if (count($pattern) !== count($segments)) {
        return null;
    }
    $params = array();
    foreach ($pattern as $i => $p) {
        if ($p !== '' && $p[0] === ':') {
            $params[substr($p, 1)] = $segments[$i];
        } elseif ($p !== $segments[$i]) {
            return null;
        }
    }
    return $params;
}

// 处理这一次请求，返回响应。
function lc_handle()
{
    $method = (string) ($_SERVER['REQUEST_METHOD'] ?? 'GET');
    $rawBody = (string) file_get_contents('php://input');
    if (strlen($rawBody) > LC_BODY_LIMIT || (int) ($_SERVER['CONTENT_LENGTH'] ?? 0) > LC_BODY_LIMIT) {
        return lc_error(413, '请求内容太大');
    }
    $url = (string) ($_SERVER['REQUEST_URI'] ?? '/');
    $q = strpos($url, '?');
    $segments = array_map('lc_pct', lc_segments($q === false ? $url : substr($url, 0, $q)));
    $pathMatched = false;
    foreach (LcRoutes::$list as $r) {
        $params = lc_match($r['segments'], $segments);
        if ($params === null) {
            continue;
        }
        $pathMatched = true;
        if ($r['method'] !== $method) {
            continue;
        }
        $req = new LcRequest();
        $req->params = $params;
        $req->rawQuery = $q === false ? '' : substr($url, $q + 1);
        $req->headers = lc_read_headers();
        $req->rawBody = $rawBody;
        try {
            $out = call_user_func($r['handler'], $req);
        } catch (Throwable $e) {
            error_log((string) $e);
            return lc_error(500, '服务器内部出错');
        }
        // 没有碰到“返回”积木：204 空响应
        return is_array($out) ? $out : array('status' => 204, 'type' => '', 'body' => '');
    }
    return $pathMatched ? lc_error(405, '这个地址不支持这种请求方式') : lc_error(404, '没有这个接口');
}

// 放在 server.php 的最后：处理这一次请求。端口不在这里定——它写在启动命令里（php -S 0.0.0.0:端口 server.php）。
function lc_start()
{
    ini_set('default_mimetype', ''); // 不让 PHP 自己加 Content-Type: text/html
    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
        // 浏览器跨域调用前的“预检”
        lc_write(array('status' => 204, 'type' => '', 'body' => ''), array('Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS', 'Access-Control-Allow-Headers: *'));
        return;
    }
    try {
        $out = lc_handle();
    } catch (Throwable $e) {
        error_log((string) $e);
        $out = lc_error(500, '服务器内部出错');
    }
    try {
        lc_db_close(); // 集合有改动就写回文件、放开锁
    } catch (Throwable $e) {
        error_log((string) $e);
        $out = lc_error(500, '服务器内部出错');
    }
    lc_write($out);
}
''';
