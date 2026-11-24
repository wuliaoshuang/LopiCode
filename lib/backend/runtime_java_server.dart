/// Java 运行时小库的源码（路由、HTTP 服务、启动；生成的工程里的 `LcServer.java`）。每份工程都一样。
///
/// 只用 JDK 自带的东西。值的规矩见 backend_ir.dart 的 `kBeRuntimeFns`，改这里的行为要同时改别的语言的小库
/// （`test/backend_conformance_test.dart` 会让各语言跑同一套请求、比对响应是否逐字节相同）。
///
/// 没有用 JDK 自带的 com.sun.net.httpserver，原因写在源码开头：它会拒掉写法不对的百分号、吃掉开头的双斜杠。
library;

const String kJavaRuntimeServerSource = r'''
// LopiCode 后端运行时小库（Java）：路由、一个很小的 HTTP 服务、启动。
//
// 没有用 JDK 自带的 com.sun.net.httpserver：它会先把请求的地址解析一遍，碰到写法不对的百分号（/a/%zz）直接回 400，
// 开头的两个斜杠也会被当成主机名——和别的语言的规矩对不上。所以这里直接用 ServerSocket 读请求（一个连接只处理一个请求）。
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

final class LcServer {
    private LcServer() {}

    private static final int HEAD_LIMIT = 65536; // 请求行加请求头最多这么多字节
    private static final int SOCKET_TIMEOUT_MS = 30000; // 对方 30 秒不说话就挂断

    // —— 请求的地址 ——

    private static boolean isHex(char c) {
        return Lc.isDigit(c) || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }

    /** 百分号解码；写法不对（%zz、解出来不是合法 UTF-8）就原样返回。 */
    static String pct(String s) {
        if (s.indexOf('%') < 0) return s;
        byte[] raw = s.getBytes(StandardCharsets.UTF_8);
        ByteArrayOutputStream out = new ByteArrayOutputStream(raw.length);
        for (int i = 0; i < raw.length; i++) {
            if (raw[i] != '%') {
                out.write(raw[i]);
                continue;
            }
            if (i + 2 >= raw.length || !isHex((char) raw[i + 1]) || !isHex((char) raw[i + 2])) return s;
            out.write(Character.digit((char) raw[i + 1], 16) * 16 + Character.digit((char) raw[i + 2], 16));
            i += 2;
        }
        try {
            return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(out.toByteArray())).toString();
        } catch (CharacterCodingException e) {
            return s;
        }
    }

    static Map<String, String> parseQuery(String raw) {
        Map<String, String> out = new HashMap<>();
        for (String part : raw.split("&", -1)) {
            if (part.isEmpty()) continue;
            int i = part.indexOf('=');
            String key = pct((i < 0 ? part : part.substring(0, i)).replace('+', ' '));
            String value = i < 0 ? "" : pct(part.substring(i + 1).replace('+', ' '));
            out.putIfAbsent(key, value);
        }
        return out;
    }

    private static List<String> split(String path) {
        List<String> out = new ArrayList<>();
        for (String s : path.split("/", -1)) {
            if (!s.isEmpty()) out.add(s);
        }
        return out;
    }

    // —— 路由 ——

    private static final class Entry {
        final String method;
        final List<String> segments;
        final Lc.Handler handler;

        Entry(String method, List<String> segments, Lc.Handler handler) {
            this.method = method;
            this.segments = segments;
            this.handler = handler;
        }
    }

    private static final List<Entry> ROUTES = new ArrayList<>();

    static void route(String method, String path, Lc.Handler handler) {
        ROUTES.add(new Entry(method, split(path), handler));
    }

    /** 路径对得上就返回参数表，否则 null。 */
    private static Map<String, String> match(List<String> pattern, List<String> segments) {
        if (pattern.size() != segments.size()) return null;
        Map<String, String> params = new HashMap<>();
        for (int i = 0; i < pattern.size(); i++) {
            String want = pattern.get(i);
            if (want.startsWith(":")) {
                params.put(want.substring(1), segments.get(i));
            } else if (!want.equals(segments.get(i))) {
                return null;
            }
        }
        return params;
    }

    private static Lc.Response error(int status, String message) {
        return Lc.sendJson((double) status, Lc.obj("error", message));
    }

    private static Lc.Response dispatch(String method, String target, Map<String, String> headers, byte[] rawBody) {
        int q = target.indexOf('?');
        List<String> segments = new ArrayList<>();
        for (String s : split(q < 0 ? target : target.substring(0, q))) segments.add(pct(s));
        boolean pathMatched = false;
        for (Entry entry : ROUTES) {
            Map<String, String> params = match(entry.segments, segments);
            if (params == null) continue;
            pathMatched = true;
            if (!entry.method.equals(method)) continue;
            try {
                Lc.Response out = entry.handler.handle(new Lc.Request(params, q < 0 ? "" : target.substring(q + 1), headers, rawBody));
                // 没有碰到“返回”积木：204 空响应
                return out != null ? out : new Lc.Response(204, "", new byte[0]);
            } catch (Throwable problem) { // 包括套得太深把栈用完的情况
                problem.printStackTrace(Lc.ERR);
                return error(500, "服务器内部出错");
            }
        }
        return pathMatched ? error(405, "这个地址不支持这种请求方式") : error(404, "没有这个接口");
    }

    // —— HTTP ——

    private static String reason(int status) {
        switch (status) {
            case 200:
                return "OK";
            case 201:
                return "Created";
            case 204:
                return "No Content";
            case 304:
                return "Not Modified";
            case 400:
                return "Bad Request";
            case 401:
                return "Unauthorized";
            case 403:
                return "Forbidden";
            case 404:
                return "Not Found";
            case 405:
                return "Method Not Allowed";
            case 413:
                return "Payload Too Large";
            case 500:
                return "Internal Server Error";
            default:
                return status < 300 ? "OK" : status < 400 ? "Redirect" : "Error";
        }
    }

    private static void send(OutputStream out, Lc.Response res, String extraHeaders) throws IOException {
        send(out, res, extraHeaders, true);
    }

    /** withBody 是 false 时只发响应头（HEAD 请求）。 */
    private static void send(OutputStream out, Lc.Response res, String extraHeaders, boolean withBody) throws IOException {
        StringBuilder head = new StringBuilder();
        head.append("HTTP/1.1 ").append(res.status).append(' ').append(reason(res.status)).append("\r\n");
        head.append("Access-Control-Allow-Origin: *\r\n").append(extraHeaders);
        boolean empty = res.status == 204 || res.status == 304;
        if (!empty) {
            head.append("Content-Type: ").append(res.contentType).append("\r\n");
            head.append("Content-Length: ").append(res.body.length).append("\r\n");
        }
        head.append("Connection: close\r\n\r\n");
        out.write(head.toString().getBytes(StandardCharsets.ISO_8859_1));
        if (!empty && withBody) out.write(res.body);
        out.flush();
    }

    /** 读到空行为止（请求行 + 请求头），返回各行；对方没发完就断开返回 null。 */
    private static List<String> readHead(InputStream in) throws IOException {
        List<String> lines = new ArrayList<>();
        ByteArrayOutputStream line = new ByteArrayOutputStream();
        for (int total = 0; total < HEAD_LIMIT; total++) {
            int c = in.read();
            if (c < 0) return null;
            if (c != '\n') {
                line.write(c);
                continue;
            }
            String text = line.toString(StandardCharsets.ISO_8859_1);
            if (text.endsWith("\r")) text = text.substring(0, text.length() - 1);
            line.reset();
            if (text.isEmpty()) {
                if (lines.isEmpty()) continue; // 请求行前面的空行不算
                return lines;
            }
            lines.add(text);
        }
        return null;
    }

    private static void serve(Socket socket) {
        try (Socket s = socket) {
            s.setSoTimeout(SOCKET_TIMEOUT_MS);
            InputStream in = new java.io.BufferedInputStream(s.getInputStream());
            OutputStream out = new java.io.BufferedOutputStream(s.getOutputStream());
            List<String> head = readHead(in);
            if (head == null) return;
            String[] first = head.get(0).split(" ", -1);
            if (first.length != 3 || !first[2].startsWith("HTTP/")) {
                send(out, Lc.sendText(400.0, "看不懂这个请求"), "");
                return;
            }
            String method = first[0];
            Map<String, String> headers = new HashMap<>();
            for (String line : head.subList(1, head.size())) {
                int colon = line.indexOf(':');
                if (colon <= 0) continue;
                String name = line.substring(0, colon).trim().toLowerCase(Locale.ROOT);
                String value = line.substring(colon + 1).trim();
                headers.merge(name, value, (a, b) -> a + ", " + b); // 同名的请求头用逗号连起来
            }
            String lengthText = headers.getOrDefault("content-length", "0");
            long length = lengthText.matches("[0-9]{1,12}") ? Long.parseLong(lengthText) : 0;
            if (length > Lc.BODY_LIMIT) {
                send(out, error(413, "请求内容太大"), "");
                return;
            }
            if (headers.getOrDefault("expect", "").toLowerCase(Locale.ROOT).contains("100-continue")) {
                out.write("HTTP/1.1 100 Continue\r\n\r\n".getBytes(StandardCharsets.ISO_8859_1));
                out.flush();
            }
            byte[] rawBody = in.readNBytes((int) length);
            if (rawBody.length < length) return; // 对方没发完就断开了
            if (method.equals("OPTIONS")) {
                // 浏览器跨域调用前的“预检”
                send(out, new Lc.Response(204, "", new byte[0]), "Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: *\r\n");
                return;
            }
            send(out, dispatch(method, first[1], headers, rawBody), "", !method.equals("HEAD"));
        } catch (IOException e) {
            // 对方中途断开、超时：这个连接不管了
        } catch (Throwable problem) {
            problem.printStackTrace(Lc.ERR);
        }
    }

    static void start(int defaultPort) {
        String env = System.getenv("PORT");
        int port = env != null && env.matches("[0-9]{1,5}") && Integer.parseInt(env) <= 65535 ? Integer.parseInt(env) : defaultPort;
        String host = System.getenv("HOST");
        if (host == null || host.isEmpty()) host = "0.0.0.0";
        ExecutorService pool = Executors.newCachedThreadPool(task -> {
            Thread t = new Thread(task, "lc-request");
            t.setDaemon(true);
            return t;
        });
        try (ServerSocket server = new ServerSocket()) {
            server.setReuseAddress(true);
            server.bind(new InetSocketAddress(host, port), 128);
            Lc.OUT.println("后端已启动：http://" + host + ":" + server.getLocalPort());
            while (true) {
                Socket socket = server.accept();
                pool.execute(() -> serve(socket));
            }
        } catch (IOException e) {
            Lc.ERR.println("启动失败：" + e.getMessage());
            System.exit(1);
        }
    }
}
''';
