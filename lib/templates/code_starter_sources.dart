/// 纯代码起步模板的源码（一）：Node.js、Python、Go、Java、Dart——这五种在本机实际启动并请求过
/// （test/code_starters_test.dart；机器上没有对应工具时那一条会跳过）。
///
/// 每份都是同一个小服务：`GET /` 回一句问候（JSON），`GET /health` 回 `{"status":"ok"}`，其余 404。
/// 端口读环境变量 `PORT`（默认 8080），`HOST` 默认 `0.0.0.0`；启动后打印一行 `后端已启动：http://主机:端口`。
/// 源码里不放用户填的项目名（只进 README），所以不存在转义问题。
library;

const String kStarterNode = r'''
// 最小的 HTTP 服务：只用 Node 自带的 node:http，不用装任何包。
// 启动：node server.js      端口默认 8080，可以用环境变量 PORT 改。
'use strict';
const http = require('node:http');

const PORT = Number(process.env.PORT ?? 8080);
const HOST = process.env.HOST || '0.0.0.0';

function sendJson(res, status, data) {
  const body = JSON.stringify(data);
  res.writeHead(status, {
    'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': Buffer.byteLength(body),
    'Access-Control-Allow-Origin': '*',
  });
  res.end(body);
}

const server = http.createServer((req, res) => {
  const path = new URL(req.url, 'http://localhost').pathname;
  if (req.method === 'GET' && path === '/') {
    return sendJson(res, 200, { message: '你好，这里是你的后端' });
  }
  if (req.method === 'GET' && path === '/health') {
    return sendJson(res, 200, { status: 'ok' });
  }
  // 在这里加你自己的接口
  sendJson(res, 404, { error: '没有这个接口' });
});

server.listen(PORT, HOST, () => {
  console.log(`后端已启动：http://${HOST}:${server.address().port}`);
});
''';

const String kStarterPython = r'''
# 最小的 HTTP 服务：只用 Python 标准库，不用装任何包。
# 启动：python3 server.py      端口默认 8080，可以用环境变量 PORT 改。
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit


class Handler(BaseHTTPRequestHandler):
    def send_json(self, status, data):
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def route(self):
        path = urlsplit(self.path).path
        if self.command == "GET" and path == "/":
            self.send_json(200, {"message": "你好，这里是你的后端"})
        elif self.command == "GET" and path == "/health":
            self.send_json(200, {"status": "ok"})
        else:
            # 在这里加你自己的接口
            self.send_json(404, {"error": "没有这个接口"})

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = route

    def log_message(self, fmt, *args):
        pass  # 不把每次请求都打到终端；想看就删掉这个函数


if __name__ == "__main__":
    host = os.environ.get("HOST", "0.0.0.0")
    port = int(os.environ.get("PORT", "8080"))
    server = ThreadingHTTPServer((host, port), Handler)
    print(f"后端已启动：http://{host}:{server.server_address[1]}", flush=True)
    server.serve_forever()
''';

const String kStarterGo = r'''
// 最小的 HTTP 服务：只用 Go 标准库的 net/http，不用装任何包。
// 启动：go run .      端口默认 8080，可以用环境变量 PORT 改。
package main

import (
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
)

func sendJSON(w http.ResponseWriter, status int, data any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(data)
}

func env(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		switch {
		case r.Method == http.MethodGet && r.URL.Path == "/":
			sendJSON(w, 200, map[string]string{"message": "你好，这里是你的后端"})
		case r.Method == http.MethodGet && r.URL.Path == "/health":
			sendJSON(w, 200, map[string]string{"status": "ok"})
		default:
			// 在这里加你自己的接口
			sendJSON(w, 404, map[string]string{"error": "没有这个接口"})
		}
	})

	host := env("HOST", "0.0.0.0")
	listener, err := net.Listen("tcp", net.JoinHostPort(host, env("PORT", "8080")))
	if err != nil {
		fmt.Fprintln(os.Stderr, "启动失败：", err)
		os.Exit(1)
	}
	fmt.Printf("后端已启动：http://%s:%d\n", host, listener.Addr().(*net.TCPAddr).Port)
	if err := http.Serve(listener, mux); err != nil {
		fmt.Fprintln(os.Stderr, "服务停了：", err)
		os.Exit(1)
	}
}
''';

const String kStarterGoMod = '''
module app

go 1.21
''';

const String kStarterJava = r'''
// 最小的 HTTP 服务：只用 JDK 自带的 com.sun.net.httpserver，不用装任何包。
// 启动：java Main.java      端口默认 8080，可以用环境变量 PORT 改。
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.OutputStream;
import java.io.PrintStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;

public class Main {
    static void sendJson(HttpExchange exchange, int status, String json) throws IOException {
        byte[] body = json.getBytes(StandardCharsets.UTF_8);
        exchange.getResponseHeaders().set("Content-Type", "application/json; charset=utf-8");
        exchange.getResponseHeaders().set("Access-Control-Allow-Origin", "*");
        exchange.sendResponseHeaders(status, body.length);
        try (OutputStream out = exchange.getResponseBody()) {
            out.write(body);
        }
    }

    static String env(String key, String fallback) {
        String value = System.getenv(key);
        return value == null || value.isEmpty() ? fallback : value;
    }

    public static void main(String[] args) throws IOException {
        String host = env("HOST", "0.0.0.0");
        int port = Integer.parseInt(env("PORT", "8080"));
        HttpServer server = HttpServer.create(new InetSocketAddress(host, port), 0);
        server.createContext("/", exchange -> {
            String path = exchange.getRequestURI().getPath();
            boolean isGet = "GET".equals(exchange.getRequestMethod());
            if (isGet && path.equals("/")) {
                sendJson(exchange, 200, "{\"message\":\"你好，这里是你的后端\"}");
            } else if (isGet && path.equals("/health")) {
                sendJson(exchange, 200, "{\"status\":\"ok\"}");
            } else {
                // 在这里加你自己的接口
                sendJson(exchange, 404, "{\"error\":\"没有这个接口\"}");
            }
        });
        server.start();
        PrintStream out = new PrintStream(System.out, true, StandardCharsets.UTF_8);
        out.println("后端已启动：http://" + host + ":" + server.getAddress().getPort());
    }
}
''';

const String kStarterDart = r'''
// 最小的 HTTP 服务：只用 Dart 自带的 dart:io，不用装任何包。
// 启动：dart run server.dart      端口默认 8080，可以用环境变量 PORT 改。
import 'dart:convert';
import 'dart:io';

Future<void> sendJson(HttpRequest request, int status, Object data) async {
  request.response
    ..statusCode = status
    ..headers.contentType = ContentType('application', 'json', charset: 'utf-8')
    ..headers.set('Access-Control-Allow-Origin', '*')
    ..write(jsonEncode(data));
  await request.response.close();
}

Future<void> main() async {
  final host = Platform.environment['HOST'] ?? '0.0.0.0';
  final port = int.tryParse(Platform.environment['PORT'] ?? '') ?? 8080;
  final server = await HttpServer.bind(host, port);
  stdout.writeln('后端已启动：http://$host:${server.port}');
  await for (final request in server) {
    final path = request.uri.path;
    if (request.method == 'GET' && path == '/') {
      await sendJson(request, 200, {'message': '你好，这里是你的后端'});
    } else if (request.method == 'GET' && path == '/health') {
      await sendJson(request, 200, {'status': 'ok'});
    } else {
      // 在这里加你自己的接口
      await sendJson(request, 404, {'error': '没有这个接口'});
    }
  }
}
''';
