/// 规矩版本 2 的小库·Java·宿主那一半（`LcHost.java`）：宿主接口、格子、要等的事、开服务。
/// 细则见 docs/blocks-v5-parts/C-library-system.md 9.1 和 B-gen-notes.md 第 12 节。只用 JDK 自带的（开服务是自己用 ServerSocket 读请求，原因见源码里“开服务”一节）。
library;

const String kRt2JavaHost = r'''
// LopiCode 积木的小库（Java，严格规矩）·宿主那一半。由 LopiCode 生成，别手改。
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.TreeMap;
import java.util.concurrent.CountDownLatch;
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
  // 没有用 JDK 自带的 com.sun.net.httpserver：它先把请求的地址解析一遍，路径以两个斜杠开头、百分号写法不对的请求自己就回 400，
  // 到不了处理函数，和别的语言对不上。所以直接用 ServerSocket 读请求（一个连接只处理一个请求，一个连接一条虚拟线）。
  private static final int BODY_LIMIT = 1048576;
  private static final int HEAD_LIMIT = 65536; // 请求行加请求头最多这么多字节
  private static final int SOCKET_TIMEOUT_MS = 30000; // 对方 30 秒不说话就挂断
  private static String reason(int status) {
    return switch (status) {
      case 200 -> "OK";
      case 201 -> "Created";
      case 204 -> "No Content";
      case 304 -> "Not Modified";
      case 400 -> "Bad Request";
      case 401 -> "Unauthorized";
      case 403 -> "Forbidden";
      case 404 -> "Not Found";
      case 405 -> "Method Not Allowed";
      case 413 -> "Payload Too Large";
      case 500 -> "Internal Server Error";
      default -> status < 200 ? "Continue" : status < 300 ? "OK" : status < 400 ? "Redirect" : "Error";
    };
  }
  private static String headerSafe(String s) { return s.replace('\r', ' ').replace('\n', ' '); }
  private static void writeRaw(OutputStream out, boolean head, int status, TreeMap<String, Object> headers, String text) throws IOException {
    byte[] bytes = text.getBytes(StandardCharsets.UTF_8);
    boolean noBody = status == 204 || status == 304 || status < 200;
    StringBuilder h = new StringBuilder();
    h.append("HTTP/1.1 ").append(status).append(' ').append(reason(status)).append("\r\n");
    for (Map.Entry<String, Object> e : headers.entrySet()) {
      String low = e.getKey().toLowerCase(java.util.Locale.ROOT);
      if (low.equals("content-length") || low.equals("connection") || low.equals("transfer-encoding")) continue;
      h.append(headerSafe(e.getKey())).append(": ").append(headerSafe(Lc.dtext(e.getValue()))).append("\r\n");
    }
    if (!noBody) h.append("Content-Length: ").append(bytes.length).append("\r\n");
    h.append("Connection: close\r\n\r\n");
    out.write(h.toString().getBytes(StandardCharsets.UTF_8));
    if (!noBody && !head) out.write(bytes);
    out.flush();
  }
  private static void hostError(OutputStream out, boolean head, int status, String message) throws IOException {
    TreeMap<String, Object> h = Lc.dict(), b = Lc.dict();
    h.put("Content-Type", "application/json; charset=utf-8");
    b.put("error", message);
    writeRaw(out, head, status, h, Lc.toJson(b));
  }
  /** 读到空行为止（请求行＋请求头），交回各行；对方没发完就断开、或者太长＝null。 */
  private static java.util.ArrayList<String> readHead(InputStream in) throws IOException {
    java.util.ArrayList<String> lines = new java.util.ArrayList<>();
    java.io.ByteArrayOutputStream line = new java.io.ByteArrayOutputStream();
    for (int total = 0; total < HEAD_LIMIT; total++) {
      int c = in.read();
      if (c < 0) return null;
      if (c != '\n') {
        line.write(c);
        continue;
      }
      String text = line.toString(StandardCharsets.UTF_8);
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
  private static void serveOne(InputStream in, OutputStream out, Lc.Fn1<TreeMap<String, Object>, TreeMap<String, Object>> handler) throws IOException {
    java.util.ArrayList<String> head = readHead(in);
    if (head == null) return;
    String[] first = head.get(0).split(" ", -1);
    if (first.length != 3 || !first[2].startsWith("HTTP/") || first[1].isEmpty()) {
      hostError(out, false, 400, "看不懂这个请求");
      return;
    }
    String method = first[0], target = first[1];
    boolean isHead = method.equals("HEAD");
    TreeMap<String, Object> headers = Lc.dict();
    for (String l : head.subList(1, head.size())) {
      int colon = l.indexOf(':');
      if (colon <= 0) continue;
      String name = l.substring(0, colon).trim().toLowerCase(java.util.Locale.ROOT);
      String value = l.substring(colon + 1).replaceAll("^[ \\t]+|[ \\t]+$", "");
      Object old = headers.get(name);
      headers.put(name, old == null ? value : old + ", " + value); // 重名的用“, ”连
    }
    String lengthText = headers.get("content-length") instanceof String t ? t : "0";
    long length = lengthText.matches("[0-9]{1,12}") ? Long.parseLong(lengthText) : 0;
    if (length > BODY_LIMIT) {
      hostError(out, isHead, 413, "请求内容太大");
      return;
    }
    if (headers.get("expect") instanceof String ex && ex.toLowerCase(java.util.Locale.ROOT).contains("100-continue")) {
      out.write("HTTP/1.1 100 Continue\r\n\r\n".getBytes(StandardCharsets.ISO_8859_1));
      out.flush();
    }
    byte[] raw = in.readNBytes((int) length);
    if (raw.length < length) return; // 对方没发完就断开了
    String body;
    try {
      body = StandardCharsets.UTF_8.newDecoder().decode(ByteBuffer.wrap(raw)).toString();
    } catch (CharacterCodingException e) {
      body = null;
    }
    // 请求行里写的是整个网址（http://主机/路径）时只要路径那一段；别的原样，不解码、不收拾斜杠。
    if (!target.startsWith("/") && target.matches("^[A-Za-z][A-Za-z0-9+.-]*://.*")) {
      int slash = target.indexOf('/', target.indexOf("://") + 3);
      target = slash < 0 ? "/" : target.substring(slash);
    }
    int hash = target.indexOf('#');
    if (hash >= 0) target = target.substring(0, hash);
    int q = target.indexOf('?');
    TreeMap<String, Object> request = Lc.dict();
    request.put("method", method);
    request.put("path", q < 0 ? target : target.substring(0, q));
    request.put("query", q < 0 ? "" : target.substring(q + 1));
    request.put("headers", headers);
    request.put("body", body);
    TreeMap<String, Object> res;
    try {
      res = handler.call(request);
    } catch (Lc.LcError e) {
      Lc.errLine("出错：" + e.getMessage());
      hostError(out, isHead, 500, "服务器内部出错");
      return;
    } catch (RuntimeException | StackOverflowError e) {
      java.io.StringWriter w = new java.io.StringWriter();
      e.printStackTrace(new java.io.PrintWriter(w));
      Lc.errLine(w.toString().stripTrailing());
      hostError(out, isHead, 500, "服务器内部出错");
      return;
    }
    Object st = res == null ? null : res.get("status");
    double status = st instanceof Double d ? d : st instanceof Long n ? (double) n : -1;
    if (status != Math.floor(status) || status < 100 || status > 599) {
      Lc.errLine("处理函数返回的响应不对（要一个字典，status 是 100 到 599 的整数）");
      hostError(out, isHead, 500, "服务器内部出错");
      return;
    }
    TreeMap<String, Object> hs = Lc.dict();
    if (res.get("headers") instanceof TreeMap<?, ?> m) {
      for (Map.Entry<?, ?> e : m.entrySet()) hs.put((String) e.getKey(), e.getValue());
    }
    writeRaw(out, isHead, (int) status, hs, Lc.dtext(res.get("body")));
  }
  private static void serveSocket(Socket socket, Lc.Fn1<TreeMap<String, Object>, TreeMap<String, Object>> handler) {
    try (Socket s = socket) {
      s.setSoTimeout(SOCKET_TIMEOUT_MS);
      serveOne(new java.io.BufferedInputStream(s.getInputStream()), new java.io.BufferedOutputStream(s.getOutputStream()), handler);
    } catch (IOException e) {
      // 对方中途断开、超时：这个连接不管了
    } catch (RuntimeException e) {
      Lc.errLine("回应没写出去：" + e);
    }
  }
  /** 一直服务，不返回；端口用不了＝出错。 */
  static void hostServe(long port, String host, Lc.Fn1<TreeMap<String, Object>, TreeMap<String, Object>> handler) {
    if (port < 0 || port > 65535) Lc.fail("开不了服务：端口要在 0 到 65535 之间");
    ServerSocket server = null;
    try {
      server = new ServerSocket();
      server.setReuseAddress(true);
      server.bind(new InetSocketAddress(host, (int) port), 128);
    } catch (IOException | RuntimeException e) {
      try {
        if (server != null) server.close();
      } catch (IOException e2) {
        Lc.errLine("端口没关掉");
      }
      Lc.fail("开不了服务：" + host + ":" + port + " 用不了");
      return;
    }
    Lc.log("后端已启动：http://" + host + ":" + server.getLocalPort());
    try (ServerSocket listening = server) {
      while (true) {
        Socket socket = listening.accept();
        Thread.ofVirtual().start(() -> serveSocket(socket, handler));
      }
    } catch (IOException e) {
      Lc.fail("服务停了：" + e.getMessage());
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
    // 方括号只在主机那一段（:// 后面到第一个 / ? # 之前，IPv6 地址）原样；后面的 java.net.URI 不认，转义掉（对方解出来是一样的）。
    int pathFrom = s.indexOf("://") + 3;
    while (pathFrom < s.length() && "/?#".indexOf(s.charAt(pathFrom)) < 0) pathFrom++;
    for (int i = 0; i < raw.length; i++) {
      int c = raw[i] & 0xFF;
      if ((c == '[' || c == ']') && i >= pathFrom) { out.append(c == '[' ? "%5B" : "%5D"); continue; }
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
