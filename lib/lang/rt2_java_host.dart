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
}
''';
