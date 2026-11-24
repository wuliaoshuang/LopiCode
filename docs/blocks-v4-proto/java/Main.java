import java.util.*;
public class Main {
  interface Fn { Object call(Object... args); }
  static class Router {
    Object routes;
    Router() { this.routes = new ArrayList<Object>(); }
    @SuppressWarnings("unchecked")
    Object on(Object method, Object path, Object handler) {
      Map<String, Object> r = new LinkedHashMap<>(); r.put("method", method); r.put("path", path); r.put("handler", handler);
      ((List<Object>) routes).add(r); return null;
    }
    @SuppressWarnings("unchecked")
    Object handle(Object method, Object path) {
      for (Object it : (List<Object>) routes) {
        Map<String, Object> r = (Map<String, Object>) it;
        if (Objects.equals(r.get("method"), method) && Objects.equals(r.get("path"), path)) {
          try { Map<String, Object> req = new LinkedHashMap<>(); req.put("path", path); return ((Fn) r.get("handler")).call(req); }
          catch (RuntimeException e) { return "500 " + e.getMessage(); }
        }
      }
      return "404";
    }
  }
  static class LoggingRouter extends Router {
    @Override Object handle(Object method, Object path) {
      Object out = super.handle(method, path);
      System.out.println(method + " " + path + " -> " + out); return out;
    }
  }
  static Fn makeCounter() {
    final Object[] n = {0.0};            // 被闭包改写的局部变量要装进“盒子”
    return (args) -> { n[0] = (Double) n[0] + 1; return n[0]; };
  }
  static String num(Object v) { double d = (Double) v; return d == Math.rint(d) ? String.valueOf((long) d) : String.valueOf(d); }
  public static void main(String[] a) throws Exception {
    System.setOut(new java.io.PrintStream(System.out, true, "UTF-8"));
    Router app = new LoggingRouter();
    Fn next = makeCounter();
    app.on("GET", "/hello", (Fn) (args) -> "200 你好 #" + num(next.call()));
    app.on("GET", "/boom", (Fn) (args) -> { throw new RuntimeException("坏了"); });
    app.handle("GET", "/hello"); app.handle("GET", "/hello"); app.handle("GET", "/boom"); app.handle("GET", "/nope");
  }
}
