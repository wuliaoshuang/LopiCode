/// Java 运行时小库的源码（主体：值的规矩、运算、数据集合、读请求、写响应、请求别的网址；生成的工程里的 `Lc.java`）。每份工程都一样。
///
/// 只用 JDK 自带的东西。值的规矩见 backend_ir.dart 的 `kBeRuntimeFns`，改这里的行为要同时改别的语言的小库
/// （`test/backend_conformance_test.dart` 会让各语言跑同一套请求、比对响应是否逐字节相同）。
library;

const String kJavaRuntimeSource = r'''
// LopiCode 后端运行时小库（Java，只用 JDK 自带的东西，不用装任何包）。
// 每份生成的工程都一样，不用改；你的接口在 Main.java 里。
//
// 这个文件：值的规矩、运算、数据集合、读请求、写响应、请求别的网址。
// 值一律是 Object：null / Boolean / Double / String / List<Object> / Map<String, Object>。
import java.io.ByteArrayOutputStream;
import java.io.FileDescriptor;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.io.PrintStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

public final class Lc {
    private Lc() {}

    static final int BODY_LIMIT = 1048576; // 请求内容最多 1MB
    static final int REPEAT_LIMIT = 10000; // “重复”最多做这么多遍
    static final int FETCH_TIMEOUT_MS = 10000; // “请求别的网址”最多等 10 秒
    static final int JSON_DEPTH_LIMIT = 64; // 请求内容的 JSON 最多套这么多层

    // 标准输出一律用 UTF-8（系统默认编码不是 UTF-8 时也能打印中文）。
    static final PrintStream OUT = new PrintStream(new FileOutputStream(FileDescriptor.out), true, StandardCharsets.UTF_8);
    static final PrintStream ERR = new PrintStream(new FileOutputStream(FileDescriptor.err), true, StandardCharsets.UTF_8);

    /** 一次请求。 */
    public static final class Request {
        final Map<String, String> params;
        final String rawQuery;
        final Map<String, String> headers; // 名字已经转成小写
        final byte[] rawBody;
        Map<String, String> query;
        boolean parsed;
        Object body;

        Request(Map<String, String> params, String rawQuery, Map<String, String> headers, byte[] rawBody) {
            this.params = params;
            this.rawQuery = rawQuery;
            this.headers = headers;
            this.rawBody = rawBody;
        }
    }

    /** 一个响应。接口函数返回 null 表示“没有碰到返回积木”（204）。 */
    public static final class Response {
        final int status;
        final String contentType;
        final byte[] body;

        Response(int status, String contentType, byte[] body) {
            this.status = status;
            this.contentType = contentType;
            this.body = body;
        }
    }

    /** 一个接口的处理函数。 */
    public interface Handler {
        Response handle(Request req);
    }

    // —— 值 ——

    static String kind(Object v) {
        if (v == null) return "null";
        if (v instanceof Boolean) return "bool";
        if (v instanceof Double) return "num";
        if (v instanceof String) return "text";
        return v instanceof List ? "list" : "obj";
    }

    static double fin(double n) {
        return Double.isNaN(n) || Double.isInfinite(n) ? 0 : n;
    }

    static boolean isDigit(char c) {
        return c >= '0' && c <= '9';
    }

    /** 是不是十进制数的写法：-1.5、.5、1e3（0x10、Infinity 这些不算）。 */
    static boolean isDecimal(String s) {
        int i = 0;
        int n = s.length();
        if (i < n && (s.charAt(i) == '+' || s.charAt(i) == '-')) i++;
        int whole = 0;
        while (i < n && isDigit(s.charAt(i))) {
            i++;
            whole++;
        }
        if (i < n && s.charAt(i) == '.') {
            i++;
            int frac = 0;
            while (i < n && isDigit(s.charAt(i))) {
                i++;
                frac++;
            }
            if (whole == 0 && frac == 0) return false;
        } else if (whole == 0) {
            return false;
        }
        if (i < n && (s.charAt(i) == 'e' || s.charAt(i) == 'E')) {
            i++;
            if (i < n && (s.charAt(i) == '+' || s.charAt(i) == '-')) i++;
            int exp = 0;
            while (i < n && isDigit(s.charAt(i))) {
                i++;
                exp++;
            }
            if (exp == 0) return false;
        }
        return i == n;
    }

    static boolean isBlank(char c) {
        return c == ' ' || c == '\t' || c == '\r' || c == '\n';
    }

    /** 转成数字：转不了的当 0。 */
    static double toNum(Object v) {
        if (v instanceof Double) return fin((Double) v);
        if (v instanceof String) {
            String s = (String) v;
            int from = 0;
            int to = s.length();
            while (from < to && isBlank(s.charAt(from))) from++;
            while (to > from && isBlank(s.charAt(to - 1))) to--;
            s = s.substring(from, to);
            return isDecimal(s) ? fin(Double.parseDouble(s)) : 0;
        }
        return Boolean.TRUE.equals(v) ? 1 : 0;
    }

    /** 转成文字。 */
    static String toText(Object v) {
        if (v == null) return "";
        if (v instanceof String) return (String) v;
        return LcJson.write(v);
    }

    /** 算不算“是”：空、否、0、空文字算“否”。 */
    public static boolean truthy(Object v) {
        if (v == null) return false;
        if (v instanceof Boolean) return (Boolean) v;
        if (v instanceof Double) return (Double) v != 0;
        if (v instanceof String) return !((String) v).isEmpty();
        return true;
    }

    /** “等于”：类型一样直接比；不一样就都转成文字再比。 */
    public static boolean eq(Object a, Object b) {
        String k = kind(a);
        if (!k.equals(kind(b))) return toText(a).equals(toText(b));
        switch (k) {
            case "null":
                return true;
            case "num":
                return ((Double) a).doubleValue() == ((Double) b).doubleValue();
            case "list":
            case "obj":
                return LcJson.write(a).equals(LcJson.write(b));
            default:
                return a.equals(b);
        }
    }

    // —— 运算 ——

    public static double add(Object a, Object b) {
        return fin(toNum(a) + toNum(b));
    }

    public static double sub(Object a, Object b) {
        return fin(toNum(a) - toNum(b));
    }

    public static double mul(Object a, Object b) {
        return fin(toNum(a) * toNum(b));
    }

    public static double div(Object a, Object b) {
        double d = toNum(b);
        return d == 0 ? 0 : fin(toNum(a) / d);
    }

    public static double mod(Object a, Object b) {
        double d = toNum(b);
        return d == 0 ? 0 : fin(toNum(a) % d);
    }

    public static boolean ne(Object a, Object b) {
        return !eq(a, b);
    }

    public static boolean lt(Object a, Object b) {
        return toNum(a) < toNum(b);
    }

    public static boolean le(Object a, Object b) {
        return toNum(a) <= toNum(b);
    }

    public static boolean gt(Object a, Object b) {
        return toNum(a) > toNum(b);
    }

    public static boolean ge(Object a, Object b) {
        return toNum(a) >= toNum(b);
    }

    public static boolean allOf(Object a, Object b) {
        return truthy(a) && truthy(b);
    }

    public static boolean anyOf(Object a, Object b) {
        return truthy(a) || truthy(b);
    }

    public static boolean isNot(Object x) {
        return !truthy(x);
    }

    public static boolean isNull(Object x) {
        return x == null;
    }

    public static String join(Object... items) {
        StringBuilder b = new StringBuilder();
        for (Object item : items) b.append(toText(item));
        return b.toString();
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> asObj(Object v) {
        return v instanceof Map ? (Map<String, Object>) v : null;
    }

    @SuppressWarnings("unchecked")
    static List<Object> asList(Object v) {
        return v instanceof List ? (List<Object>) v : null;
    }

    public static double size(Object x) {
        if (x instanceof List) return ((List<?>) x).size();
        if (x instanceof String) return ((String) x).codePointCount(0, ((String) x).length());
        if (x instanceof Map) return ((Map<?, ?>) x).size();
        return 0;
    }

    /** obj("title", "买菜", "done", false) → {"title": "买菜", "done": false} */
    public static Object obj(Object... pairs) {
        Map<String, Object> o = new HashMap<>();
        for (int i = 0; i + 1 < pairs.length; i += 2) o.put((String) pairs[i], pairs[i + 1]);
        return o;
    }

    public static Object field(Object o, String key) {
        Map<String, Object> m = asObj(o);
        return m == null ? null : m.get(key);
    }

    public static int times(Object x) {
        double n = toNum(x);
        return n < 0 ? 0 : n > REPEAT_LIMIT ? REPEAT_LIMIT : (int) n;
    }

    public static List<Object> items(Object x) {
        List<Object> list = asList(x);
        return list == null ? new ArrayList<>() : new ArrayList<>(list);
    }

    public static String now() {
        return Instant.now().truncatedTo(ChronoUnit.SECONDS).toString();
    }

    public static void log(Object x) {
        OUT.println(toText(x));
    }

    // —— 数据集合（存在内存里，进程重启就没了）——

    private static final class Table {
        double next = 1;
        final List<Map<String, Object>> rows = new ArrayList<>();
    }

    private static final Map<String, Table> TABLES = new HashMap<>();
    private static final Object DB_LOCK = new Object(); // 每个请求一个线程，动集合要排队

    private static Table table(String name) {
        return TABLES.computeIfAbsent(name, k -> new Table());
    }

    /** 声明一个数据集合。 */
    public static void collection(String name) {
        synchronized (DB_LOCK) {
            table(name);
        }
    }

    private static int indexOf(List<Map<String, Object>> rows, Object id) {
        double want = toNum(id);
        for (int i = 0; i < rows.size(); i++) {
            Object have = rows.get(i).get("id");
            if (have instanceof Double && (Double) have == want) return i;
        }
        return -1;
    }

    public static Object dbAll(String name) {
        synchronized (DB_LOCK) {
            return new ArrayList<Object>(table(name).rows);
        }
    }

    public static double dbCount(String name) {
        synchronized (DB_LOCK) {
            return table(name).rows.size();
        }
    }

    public static Object dbGet(String name, Object id) {
        synchronized (DB_LOCK) {
            List<Map<String, Object>> rows = table(name).rows;
            int i = indexOf(rows, id);
            return i < 0 ? null : rows.get(i);
        }
    }

    public static Object dbFind(String name, String key, Object value) {
        synchronized (DB_LOCK) {
            List<Object> out = new ArrayList<>();
            for (Map<String, Object> row : table(name).rows) {
                if (eq(row.get(key), value)) out.add(row);
            }
            return out;
        }
    }

    public static Object dbInsert(String name, Object value) {
        synchronized (DB_LOCK) {
            Table t = table(name);
            Map<String, Object> source = asObj(value);
            Map<String, Object> row = source == null ? new HashMap<>() : new HashMap<>(source);
            row.put("id", t.next);
            t.next += 1;
            t.rows.add(row);
            return row;
        }
    }

    /** 改的是一份新的记录（之前读出来的那份不会跟着变）。 */
    public static Object dbUpdate(String name, Object id, Object value) {
        synchronized (DB_LOCK) {
            List<Map<String, Object>> rows = table(name).rows;
            int i = indexOf(rows, id);
            if (i < 0) return null;
            Map<String, Object> changes = asObj(value);
            if (changes == null) return rows.get(i);
            Map<String, Object> row = new HashMap<>(rows.get(i));
            row.putAll(changes);
            row.put("id", rows.get(i).get("id"));
            rows.set(i, row);
            return row;
        }
    }

    public static boolean dbDelete(String name, Object id) {
        synchronized (DB_LOCK) {
            List<Map<String, Object>> rows = table(name).rows;
            int i = indexOf(rows, id);
            if (i < 0) return false;
            rows.remove(i);
            return true;
        }
    }

    // —— 请求 ——

    public static Object pathParam(Request req, String name) {
        return req.params.get(name);
    }

    public static Object query(Request req, String name) {
        if (req.query == null) req.query = LcServer.parseQuery(req.rawQuery);
        return req.query.get(name);
    }

    public static Object body(Request req) {
        if (!req.parsed) {
            req.parsed = true;
            req.body = LcJson.parse(req.rawBody);
        }
        return req.body;
    }

    public static Object bodyField(Request req, String name) {
        return field(body(req), name);
    }

    public static Object header(Request req, String name) {
        return req.headers.get(name.toLowerCase(Locale.ROOT));
    }

    // —— 响应 ——

    static int statusOf(Object v) {
        double n = toNum(v);
        return n >= 200 && n < 600 ? (int) n : 200;
    }

    public static Response sendJson(Object status, Object value) {
        return new Response(statusOf(status), "application/json; charset=utf-8", LcJson.write(value).getBytes(StandardCharsets.UTF_8));
    }

    public static Response sendText(Object status, Object value) {
        return new Response(statusOf(status), "text/plain; charset=utf-8", toText(value).getBytes(StandardCharsets.UTF_8));
    }

    // —— 请求别的网址 ——

    private static final String URL_KEEP = "-._~:/?#[]@!$&'()*+,;=";
    private static final String HEX = "0123456789ABCDEF";

    private static boolean isHex(byte c) {
        return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
    }

    /** 主机那一段（:// 后面到第一个 / ? # 之前）到哪里为止。 */
    private static int authorityEnd(String url) {
        int i = url.indexOf("://") + 3;
        while (i < url.length() && "/?#".indexOf(url.charAt(i)) < 0) i++;
        return i;
    }

    /** 网址里的空格、中文、写法不对的百分号先按 UTF-8 做百分号转义（各语言自己的处理不一样，这里统一）。 */
    static String encodeUrl(String s) {
        byte[] raw = s.getBytes(StandardCharsets.UTF_8);
        StringBuilder b = new StringBuilder();
        int pathFrom = authorityEnd(s); // 都是 ASCII，字节下标和字符下标一样
        for (int i = 0; i < raw.length; i++) {
            byte c = raw[i];
            boolean escaped = c == '%' && i + 2 < raw.length && isHex(raw[i + 1]) && isHex(raw[i + 2]);
            boolean letter = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z');
            // 方括号只在主机那一段（IPv6 地址）原样；后面的 Java 不认，转义掉（对方解出来是一样的）
            boolean bracket = (c == '[' || c == ']') && i >= pathFrom;
            if (escaped || letter || (c >= '0' && c <= '9') || (c > 0 && !bracket && URL_KEEP.indexOf(c) >= 0)) {
                b.append((char) c);
            } else {
                b.append('%').append(HEX.charAt((c >> 4) & 15)).append(HEX.charAt(c & 15));
            }
        }
        return b.toString();
    }

    /** 成功（2xx）返回响应的文字；失败、超时、不是 http(s) 网址、网址里带用户名密码一律返回 null。 */
    public static Object fetch(String method, Object url, Object data) {
        String target = toText(url);
        String lower = target.toLowerCase(Locale.ROOT);
        if (!lower.startsWith("http://") && !lower.startsWith("https://")) return null;
        // 主机那一段带 @（用户名密码）的不请求
        if (target.substring(target.indexOf("://") + 3, authorityEnd(target)).indexOf('@') >= 0) return null;
        HttpURLConnection conn = null;
        try {
            conn = (HttpURLConnection) URI.create(encodeUrl(target)).toURL().openConnection();
            conn.setConnectTimeout(FETCH_TIMEOUT_MS);
            conn.setReadTimeout(FETCH_TIMEOUT_MS);
            boolean post = "POST".equals(method);
            conn.setRequestMethod(post ? "POST" : "GET");
            if (post && data != null) {
                byte[] payload = LcJson.write(data).getBytes(StandardCharsets.UTF_8);
                conn.setDoOutput(true);
                conn.setFixedLengthStreamingMode(payload.length);
                conn.setRequestProperty("Content-Type", "application/json; charset=utf-8");
                try (OutputStream out = conn.getOutputStream()) {
                    out.write(payload);
                }
            }
            int code = conn.getResponseCode();
            if (code < 200 || code > 299) return null;
            try (InputStream in = conn.getInputStream()) {
                ByteArrayOutputStream all = new ByteArrayOutputStream();
                byte[] chunk = new byte[8192];
                for (int n = in.read(chunk); n >= 0; n = in.read(chunk)) all.write(chunk, 0, n);
                // 不是合法 UTF-8 的地方换成 U+FFFD
                String text = new String(all.toByteArray(), StandardCharsets.UTF_8);
                // 开头的 BOM（U+FEFF）去掉一个
                return text.startsWith("\uFEFF") ? text.substring(1) : text;
            }
        } catch (Exception e) { // 连不上、超时、网址写错……都算失败
            return null;
        } finally {
            if (conn != null) conn.disconnect();
        }
    }

    // —— 路由与启动（实现在 LcServer.java）——

    /** 登记一个接口。path 里的 :名字 是路径参数。 */
    public static void route(String method, String path, Handler handler) {
        LcServer.route(method, path, handler);
    }

    /** 启动服务。端口先看环境变量 PORT，没有就用 defaultPort；HOST 默认 0.0.0.0（所有网卡）。 */
    public static void start(int defaultPort) {
        LcServer.start(defaultPort);
    }
}
''';
