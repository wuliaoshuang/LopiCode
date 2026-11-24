/// 纯代码起步模板的源码（二）：PHP、C#、Rust、Ruby、Kotlin。
///
/// **这五种没有在本机实际运行过**（这台机器上没有对应的工具），只做了结构检查；模板说明和 README 里都如实写着。
/// 行为和（一）里的一样：`GET /` 问候、`GET /health`、其余 404；端口读 `PORT`，默认 8080。
library;

const String kStarterPhp = r'''
<?php
// 最小的 HTTP 服务：只用 PHP 自带的内置服务器，不用装任何包。
// 启动：php -S 0.0.0.0:8080 index.php      换端口就改命令里的 8080。

function send_json(int $status, array $data): void
{
    http_response_code($status);
    header('Content-Type: application/json; charset=utf-8');
    header('Access-Control-Allow-Origin: *');
    echo json_encode($data, JSON_UNESCAPED_UNICODE);
}

$path = parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH);
$method = $_SERVER['REQUEST_METHOD'];

if ($method === 'GET' && $path === '/') {
    send_json(200, ['message' => '你好，这里是你的后端']);
} elseif ($method === 'GET' && $path === '/health') {
    send_json(200, ['status' => 'ok']);
} else {
    // 在这里加你自己的接口
    send_json(404, ['error' => '没有这个接口']);
}
''';

const String kStarterCsharp = r'''
// 最小的 HTTP 服务：ASP.NET Core 的 Minimal API（.NET SDK 自带，不用另外装包）。
// 启动：dotnet run      端口默认 8080，可以用环境变量 PORT 改。
var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var host = Environment.GetEnvironmentVariable("HOST") ?? "0.0.0.0";
var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";

app.MapGet("/", () => Results.Json(new { message = "你好，这里是你的后端" }));
app.MapGet("/health", () => Results.Json(new { status = "ok" }));
// 在这里加你自己的接口
app.MapFallback(() => Results.Json(new { error = "没有这个接口" }, statusCode: 404));

Console.WriteLine($"后端已启动：http://{host}:{port}");
app.Run($"http://{host}:{port}");
''';

const String kStarterCsproj = '''
<Project Sdk="Microsoft.NET.Sdk.Web">

  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
  </PropertyGroup>

</Project>
''';

const String kStarterRust = r'''
// 最小的 HTTP 服务：只用 Rust 标准库（std::net），不用装任何包。
// 启动：cargo run      端口默认 8080，可以用环境变量 PORT 改。
// 说明：这里是手写的最简 HTTP/1.1 处理，够学习和小工具用；正式项目建议换成 axum、actix-web 之类的框架。
use std::env;
use std::io::{BufRead, BufReader, Write};
use std::net::{TcpListener, TcpStream};
use std::thread;

fn send_json(mut stream: &TcpStream, status: &str, body: &str) {
    let response = format!(
        "HTTP/1.1 {}\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: {}\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n{}",
        status,
        body.len(),
        body
    );
    let _ = stream.write_all(response.as_bytes());
}

fn handle(stream: TcpStream) {
    let mut reader = BufReader::new(&stream);
    let mut request_line = String::new();
    if reader.read_line(&mut request_line).is_err() {
        return;
    }
    // 把请求头读完（读到空行为止）
    loop {
        let mut header = String::new();
        match reader.read_line(&mut header) {
            Ok(n) if n > 2 => continue,
            _ => break,
        }
    }
    let mut parts = request_line.split_whitespace();
    let method = parts.next().unwrap_or("");
    let target = parts.next().unwrap_or("");
    let path = target.split('?').next().unwrap_or("");
    match (method, path) {
        ("GET", "/") => send_json(&stream, "200 OK", r#"{"message":"你好，这里是你的后端"}"#),
        ("GET", "/health") => send_json(&stream, "200 OK", r#"{"status":"ok"}"#),
        // 在这里加你自己的接口
        _ => send_json(&stream, "404 Not Found", r#"{"error":"没有这个接口"}"#),
    }
}

fn main() {
    let host = env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port = env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let listener = TcpListener::bind(format!("{}:{}", host, port)).expect("启动失败：端口可能被占用了");
    let actual = listener.local_addr().map(|a| a.port()).unwrap_or(0);
    println!("后端已启动：http://{}:{}", host, actual);
    for stream in listener.incoming().flatten() {
        thread::spawn(move || handle(stream));
    }
}
''';

const String kStarterCargo = '''
[package]
name = "app"
version = "0.1.0"
edition = "2021"

[dependencies]
''';

const String kStarterRuby = r'''
# 最小的 HTTP 服务：只用 Ruby 标准库（socket、json），不用装任何 gem。
# 启动：ruby server.rb      端口默认 8080，可以用环境变量 PORT 改。
# 说明：这里是手写的最简 HTTP/1.1 处理，够学习和小工具用；正式项目建议换成 Sinatra、Rails 之类的框架。
require 'socket'
require 'json'

host = ENV.fetch('HOST', '0.0.0.0')
port = ENV.fetch('PORT', '8080').to_i
server = TCPServer.new(host, port)
$stdout.sync = true
puts "后端已启动：http://#{host}:#{server.addr[1]}"

def send_json(client, status, data)
  body = JSON.generate(data)
  client.write "HTTP/1.1 #{status}\r\n" \
               "Content-Type: application/json; charset=utf-8\r\n" \
               "Content-Length: #{body.bytesize}\r\n" \
               "Access-Control-Allow-Origin: *\r\n" \
               "Connection: close\r\n\r\n" \
               "#{body}"
end

loop do
  Thread.start(server.accept) do |client|
    begin
      request_line = client.gets.to_s
      # 把请求头读完（读到空行为止）
      while (line = client.gets) && line != "\r\n"
      end
      method, target = request_line.split(' ')
      path = target.to_s.split('?').first
      if method == 'GET' && path == '/'
        send_json(client, '200 OK', { message: '你好，这里是你的后端' })
      elsif method == 'GET' && path == '/health'
        send_json(client, '200 OK', { status: 'ok' })
      else
        # 在这里加你自己的接口
        send_json(client, '404 Not Found', { error: '没有这个接口' })
      end
    ensure
      client.close
    end
  end
end
''';

const String kStarterKotlin = r'''
// 最小的 HTTP 服务：只用 JDK 自带的 com.sun.net.httpserver，不用装任何包。
// 启动：kotlinc Main.kt -include-runtime -d app.jar && java -jar app.jar
// 端口默认 8080，可以用环境变量 PORT 改。
import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import java.net.InetSocketAddress

fun sendJson(exchange: HttpExchange, status: Int, json: String) {
    val body = json.toByteArray(Charsets.UTF_8)
    exchange.responseHeaders.set("Content-Type", "application/json; charset=utf-8")
    exchange.responseHeaders.set("Access-Control-Allow-Origin", "*")
    exchange.sendResponseHeaders(status, body.size.toLong())
    exchange.responseBody.use { it.write(body) }
}

fun main() {
    val host = System.getenv("HOST") ?: "0.0.0.0"
    val port = (System.getenv("PORT") ?: "8080").toInt()
    val server = HttpServer.create(InetSocketAddress(host, port), 0)
    server.createContext("/") { exchange ->
        val path = exchange.requestURI.path
        val isGet = exchange.requestMethod == "GET"
        when {
            isGet && path == "/" -> sendJson(exchange, 200, "{\"message\":\"你好，这里是你的后端\"}")
            isGet && path == "/health" -> sendJson(exchange, 200, "{\"status\":\"ok\"}")
            // 在这里加你自己的接口
            else -> sendJson(exchange, 404, "{\"error\":\"没有这个接口\"}")
        }
    }
    server.start()
    println("后端已启动：http://$host:${server.address.port}")
}
''';
