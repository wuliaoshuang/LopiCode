/// 规矩版本 2 的小库·Java·宿主那一半（`LcHost.java`）：宿主接口、格子、要等的事、开服务。
/// 细则见 docs/blocks-v5-parts/C-library-system.md 9.1 和 B-gen-notes.md 第 12 节。只用 JDK 自带的（开服务用 jdk.httpserver）。
library;

const String kRt2JavaHost = r'''
// LopiCode 积木的小库（Java，严格规矩）·宿主那一半。由 LopiCode 生成，别手改。
import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.io.InputStream;
import java.net.InetSocketAddress;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.Executors;
import java.util.concurrent.locks.ReentrantLock;

final class LcHost {
  private LcHost() {}

  static void hostPrint(String s, String ch) {
    if (ch.equals("out")) Lc.log(s);
    else if (ch.equals("err")) Lc.errLine(s);
    else Lc.fail("通道只能是 out 或 err");
  }
  static long hostNow() { return System.currentTimeMillis(); }
  static String hostEnv(String name) { return System.getenv(name); }

  // —— 格子：每个名字一把锁。别的线同时改同一个名字＝排队；改它的函数里再改它＝报错（不然会自己等自己）——
  private static final HashMap<String, Object> store = new HashMap<>();
  private static final HashMap<String, ReentrantLock> storeLocks = new HashMap<>();
  static Object storeRead(String name) {
    synchronized (store) { return Lc.copyVal(store.get(name)); }
  }
  static Object storeUpdate(String name, Lc.Fn1<Object, Object> f) {
    ReentrantLock lock;
    synchronized (store) { lock = storeLocks.computeIfAbsent(name, k -> new ReentrantLock()); }
    if (lock.isHeldByCurrentThread()) Lc.fail("「" + name + "」这个格子正在改，不能在改它的函数里再改它");
    lock.lock();
    try {
      Object v = Lc.copyVal(f.call(storeRead(name)));
      synchronized (store) { store.put(name, v); }
      return Lc.copyVal(v);
    } finally {
      lock.unlock();
    }
  }

  // —— 要等的事：一件事一条（虚拟）线 ——
  static void hostSleep(long ms) {
    if (ms <= 0) return;
    try {
      Thread.sleep(ms);
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      Lc.fail("等的时候被打断了");
    }
  }
  /** “开始做”的结果。出了错先记着，等它的时候再抛。 */
  static final class Task<T> {
    private final CountDownLatch done = new CountDownLatch(1);
    private T val;
    private RuntimeException err;
  }
  static <T> Task<T> spawn(Lc.Fn0<T> f) {
    Task<T> t = new Task<>();
    Thread.ofVirtual().start(() -> {
      try {
        t.val = f.call();
      } catch (RuntimeException e) {
        t.err = e;
      } finally {
        t.done.countDown();
      }
    });
    return t;
  }
  static <T> T await(Task<T> t) {
    try {
      t.done.await();
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return Lc.fail("等的时候被打断了");
    }
    if (t.err != null) throw t.err;
    return t.val;
  }

  // —— 开服务 ——
  private static final int BODY_LIMIT = 1048576;
  private static void writeRaw(HttpExchange ex, int status, TreeMap<String, Object> headers, String text) throws IOException {
    byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
    boolean noBody = status == 204 || status == 304 || status < 200;
    boolean head = ex.getRequestMethod().equals("HEAD");
    for (Map.Entry<String, Object> e : headers.entrySet()) {
      if (!e.getKey().equalsIgnoreCase("content-length")) ex.getResponseHeaders().set(e.getKey(), Lc.dtext(e.getValue()));
    }
    if (head && !noBody) ex.getResponseHeaders().set("Content-Length", Integer.toString(bytes.length));
    boolean send = !noBody && !head && bytes.length > 0;
    ex.sendResponseHeaders(status, send ? bytes.length : -1);
    if (send) ex.getResponseBody().write(bytes);
    ex.close();
  }
  private static void hostError(HttpExchange ex, int status, String message) throws IOException {
    TreeMap<String, Object> h = Lc.dict(), b = Lc.dict();
    h.put("Content-Type", "application/json; charset=utf-8");
    b.put("error", message);
    writeRaw(ex, status, h, Lc.toJson(b));
  }
  private static void serveOne(HttpExchange ex, Lc.Fn1<TreeMap<String, Object>, TreeMap<String, Object>> handler) throws IOException {
    String lengthText = ex.getRequestHeaders().getFirst("Content-Length");
    long length = lengthText != null && lengthText.matches("[0-9]{1,12}") ? Long.parseLong(lengthText) : 0;
    byte[] raw = new byte[0];
    if (length <= BODY_LIMIT) {
      try (InputStream in = ex.getRequestBody()) { raw = in.readNBytes(BODY_LIMIT + 1); }
    }
    if (length > BODY_LIMIT || raw.length > BODY_LIMIT) {
      ex.getResponseHeaders().set("Connection", "close");
      hostError(ex, 413, "请求内容太大");
      return;
    }
    String body;
    try {
      body = StandardCharsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(raw)).toString();
    } catch (CharacterCodingException e) {
      body = null;
    }
    TreeMap<String, Object> headers = Lc.dict();
    for (Map.Entry<String, List<String>> e : ex.getRequestHeaders().entrySet()) {
      StringBuilder joined = new StringBuilder();
      for (String v : e.getValue()) {
        if (joined.length() > 0) joined.append(", ");
        joined.append(v.replaceAll("^[ \\t]+|[ \\t]+$", ""));
      }
      headers.put(e.getKey().toLowerCase(java.util.Locale.ROOT), joined.toString());
    }
    String rawQuery = ex.getRequestURI().getRawQuery();
    TreeMap<String, Object> request = Lc.dict();
    request.put("method", ex.getRequestMethod());
    request.put("path", ex.getRequestURI().getRawPath());
    request.put("query", rawQuery == null ? "" : rawQuery);
    request.put("headers", headers);
    request.put("body", body);
    TreeMap<String, Object> out;
    try {
      out = handler.call(request);
    } catch (Lc.LcError e) {
      Lc.errLine("出错：" + e.getMessage());
      hostError(ex, 500, "服务器内部出错");
      return;
    } catch (RuntimeException e) {
      java.io.StringWriter w = new java.io.StringWriter();
      e.printStackTrace(new java.io.PrintWriter(w));
      Lc.errLine(w.toString().stripTrailing());
      hostError(ex, 500, "服务器内部出错");
      return;
    }
    Object st = out == null ? null : out.get("status");
    double status = st instanceof Double d ? d : st instanceof Long n ? (double) n : -1;
    if (status != Math.floor(status) || status < 100 || status > 599) {
      Lc.errLine("处理函数返回的响应不对（要一个字典，status 是 100 到 599 的整数）");
      hostError(ex, 500, "服务器内部出错");
      return;
    }
    TreeMap<String, Object> hs = Lc.dict();
    if (out.get("headers") instanceof TreeMap<?, ?> m) {
      for (Map.Entry<?, ?> e : m.entrySet()) hs.put((String) e.getKey(), e.getValue());
    }
    writeRaw(ex, (int) status, hs, Lc.dtext(out.get("body")));
  }
  /** 一直服务，不返回；端口用不了＝出错。 */
  static void hostServe(long port, String host, Lc.Fn1<TreeMap<String, Object>, TreeMap<String, Object>> handler) {
    if (port < 0 || port > 65535) Lc.fail("开不了服务：端口要在 0 到 65535 之间");
    HttpServer server;
    try {
      server = HttpServer.create(new InetSocketAddress(host, (int) port), 0);
    } catch (IOException e) {
      Lc.fail("开不了服务：" + host + ":" + port + " 用不了");
      return;
    }
    server.createContext("/", ex -> {
      try {
        serveOne(ex, handler);
      } catch (IOException | RuntimeException e) {
        Lc.errLine("回应没写出去：" + e);
        ex.close();
      }
    });
    server.setExecutor(Executors.newVirtualThreadPerTaskExecutor());
    server.start();
    Lc.log("后端已启动：http://" + host + ":" + server.getAddress().getPort());
    try {
      new CountDownLatch(1).await();
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
    }
  }
  // —— 随机字节、文件、请求别的网址（细则见 docs/blocks-v5-parts/B-gen-notes.md 第 14 节）——
  static java.util.ArrayList<Long> hostRandomBytes(long n) {
    if (n < 1 || n > 1024) Lc.fail("随机字节的个数要在 1 到 1024 之间");
    byte[] raw = new byte[(int) n];
    new java.security.SecureRandom().nextBytes(raw);
    java.util.ArrayList<Long> out = new java.util.ArrayList<>();
    for (byte b : raw) out.add((long) (b & 0xFF));
    return out;
  }
  private static java.nio.file.Path filePath(String p) {
    boolean bad = p.isEmpty() || p.charAt(0) == '/' || p.charAt(0) == '\\' || p.matches("^[A-Za-z]:.*");
    for (String seg : p.split("[/\\\\]")) bad = bad || seg.equals("..");
    if (bad) Lc.fail("路径不对：只能用工程文件夹里面的相对路径");
    try {
      return java.nio.file.Paths.get(System.getProperty("user.dir")).resolve(p);
    } catch (java.nio.file.InvalidPathException e) {
      return Lc.fail("路径不对：只能用工程文件夹里面的相对路径");
    }
  }
  static String fileRead(String p) {
    java.nio.file.Path full = filePath(p);
    if (!java.nio.file.Files.exists(full)) Lc.fail("读不了文件：没有「" + p + "」");
    byte[] raw;
    try {
      raw = java.nio.file.Files.readAllBytes(full);
    } catch (IOException e) {
      return Lc.fail("读不了文件：「" + p + "」");
    }
    try {
      return StandardCharsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(raw)).toString();
    } catch (CharacterCodingException e) {
      return Lc.fail("读不了文件：「" + p + "」不是 UTF-8 文字");
    }
  }
  static void fileWrite(String p, String text) {
    java.nio.file.Path full = filePath(p);
    java.nio.file.Path tmp = full.resolveSibling(full.getFileName() + ".lctmp" + ProcessHandle.current().pid());
    try {
      if (full.getParent() != null) java.nio.file.Files.createDirectories(full.getParent());
      java.nio.file.Files.write(tmp, text.getBytes(StandardCharsets.UTF_8));
      java.nio.file.Files.move(tmp, full, java.nio.file.StandardCopyOption.REPLACE_EXISTING, java.nio.file.StandardCopyOption.ATOMIC_MOVE);
    } catch (IOException | RuntimeException e) {
      try {
        java.nio.file.Files.deleteIfExists(tmp);
      } catch (IOException e2) {
        Lc.errLine("临时文件没删掉：" + tmp);
      }
      Lc.fail("写不了文件：「" + p + "」");
    }
  }
  static boolean fileExists(String p) { return java.nio.file.Files.exists(filePath(p)); }
  static java.util.ArrayList<String> fileList(String p) {
    java.util.ArrayList<String> out = new java.util.ArrayList<>();
    try (java.util.stream.Stream<java.nio.file.Path> s = java.nio.file.Files.list(filePath(p))) {
      s.forEach(x -> out.add(x.getFileName().toString()));
    } catch (IOException | RuntimeException e) {
      if (e instanceof Lc.LcError le) throw le;
      Lc.fail("列不了文件夹：「" + p + "」");
    }
    out.sort(Lc::cmpText);
    return out;
  }
  static void fileRemove(String p) {
    java.nio.file.Path full = filePath(p);
    boolean ok = java.nio.file.Files.isRegularFile(full);
    try {
      if (ok) java.nio.file.Files.delete(full);
    } catch (IOException e) {
      ok = false;
    }
    if (!ok) Lc.fail("删不了文件：「" + p + "」");
  }
  // 网址里的空格、中文、写法不对的百分号先按 UTF-8 做百分号转义（各语言自己的处理不一样，这里统一）；# 后面的不发。
  private static String encodeUrl(String s) {
    int hash = s.indexOf('#');
    byte[] raw = (hash < 0 ? s : s.substring(0, hash)).getBytes(StandardCharsets.UTF_8);
    StringBuilder out = new StringBuilder();
    for (int i = 0; i < raw.length; i++) {
      int c = raw[i] & 0xFF;
      boolean escaped = c == '%' && i + 2 < raw.length && Character.digit(raw[i + 1], 16) >= 0 && Character.digit(raw[i + 2], 16) >= 0;
      boolean keep = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || "-._~:/?[]@!$&'()*+,;=".indexOf(c) >= 0;
      if (escaped || keep) out.append((char) c);
      else out.append('%').append("0123456789ABCDEF".charAt(c >> 4)).append("0123456789ABCDEF".charAt(c & 15));
    }
    return out.toString();
  }
  private static final List<String> FETCH_METHODS = List.of("GET", "HEAD", "POST", "PUT", "PATCH", "DELETE", "OPTIONS");
  private static final List<String> FETCH_SKIP = List.of("host", "content-length", "connection", "expect", "upgrade");
  static TreeMap<String, Object> hostFetch(String method, String url, TreeMap<String, String> headers, String body, long timeoutMs) {
    String lower = url.toLowerCase(java.util.Locale.ROOT);
    if (!lower.startsWith("http://") && !lower.startsWith("https://")) Lc.fail("请求不了：网址要以 http:// 或 https:// 开头");
    if (!FETCH_METHODS.contains(method)) Lc.fail("请求不了：不认识的方式「" + method + "」");
    if (timeoutMs <= 0) Lc.fail("请求不了：超时毫秒要大于 0");
    java.time.Duration limit = java.time.Duration.ofMillis(timeoutMs);
    try (java.net.http.HttpClient client = java.net.http.HttpClient.newBuilder().version(java.net.http.HttpClient.Version.HTTP_1_1)
        .followRedirects(java.net.http.HttpClient.Redirect.NORMAL).connectTimeout(limit).build()) {
      boolean hasBody = body != null && !method.equals("GET") && !method.equals("HEAD");
      java.net.http.HttpRequest.Builder req = java.net.http.HttpRequest.newBuilder(java.net.URI.create(encodeUrl(url))).timeout(limit)
          .method(method, hasBody ? java.net.http.HttpRequest.BodyPublishers.ofString(body, StandardCharsets.UTF_8) : java.net.http.HttpRequest.BodyPublishers.noBody());
      boolean hasType = false, hasAgent = false;
      for (Map.Entry<String, String> h : headers.entrySet()) {
        String low = h.getKey().toLowerCase(java.util.Locale.ROOT);
        if (FETCH_SKIP.contains(low)) continue;
        hasType = hasType || low.equals("content-type");
        hasAgent = hasAgent || low.equals("user-agent");
        req.setHeader(h.getKey(), h.getValue());
      }
      if (!hasAgent) req.setHeader("User-Agent", "LopiCode");
      if (hasBody && !hasType) req.setHeader("Content-Type", "text/plain; charset=utf-8");
      java.net.http.HttpResponse<byte[]> res = client.send(req.build(), java.net.http.HttpResponse.BodyHandlers.ofByteArray());
      TreeMap<String, Object> back = Lc.dict();
      for (Map.Entry<String, List<String>> h : res.headers().map().entrySet()) back.put(h.getKey().toLowerCase(java.util.Locale.ROOT), String.join(", ", h.getValue()));
      TreeMap<String, Object> out = Lc.dict();
      out.put("status", (double) res.statusCode());
      out.put("headers", back);
      out.put("body", new String(res.body(), StandardCharsets.UTF_8));
      return out;
    } catch (java.net.http.HttpTimeoutException e) {
      return Lc.fail("请求超时了");
    } catch (InterruptedException e) {
      Thread.currentThread().interrupt();
      return Lc.fail("请求不了：连不上");
    } catch (IOException | IllegalArgumentException e) {
      return Lc.fail("请求不了：连不上");
    }
  }
}
''';
