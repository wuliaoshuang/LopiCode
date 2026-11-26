/// 规矩版本 2 的小库·Java（`Lc.java`）·下半：可空、“任意”、JSON、出错、输出。上半在 rt2_java.dart。
library;

import 'package:lopicode/lang/rt2_java.dart';

/// 整份 `Lc.java`。
const String kRt2JavaSource = kRt2JavaHead + _tail;

const String _tail = r'''
  static boolean dictHas(TreeMap<String, ?> d, String k) { return d.containsKey(k); }

  // —— 小零碎（生成的代码用） ——
  /// “一直做”的条件：不写成 true，免得 Java 认定后面的代码永远到不了而不让编。
  static boolean yes() { return true; }
  static boolean ieq(long a, long b) { return a == b; }
  static boolean feq(double a, double b) { return a == b; }
  static boolean beq(boolean a, boolean b) { return a == b; }
  static double i2f(long n) { return (double) n; }
  static boolean isNull(Object x) { return x == null; }
  static boolean same(Object a, Object b) { return a == b; }
  static Object idyn(long n) { return (double) n; }
  static Object fdyn(double v) { return v; }

  // —— 任意 ——
  interface DynBody { Object call(Object[] a); }
  /** 放进“任意”里的函数：参数、结果都当任意；[orig] 是它原来带类型的样子（没有就是 null）。 */
  static final class DynFn {
    final int n;
    final DynBody f;
    final Object orig;
    DynFn(int n, DynBody f, Object orig) {
      this.n = n;
      this.f = f;
      this.orig = orig;
    }
  }
  /** 带类型的函数装进任意：[call] 负责把参数从任意取回、把结果装回去。 */
  static <F> Object dynFn(F f, int n, Fn2<F, Object[], Object> call) { return f == null ? null : new DynFn(n, a -> call.call(f, a), f); }
  static <T> Object opt(T x, Fn1<T, Object> f) { return x == null ? null : f.call(x); }
  static <T> ArrayList<Object> listDyn(ArrayList<T> xs, Fn1<T, Object> f) {
    if (xs == null) return null;
    ArrayList<Object> out = new ArrayList<>();
    for (T x : xs) out.add(f.call(x));
    return out;
  }
  static <V> TreeMap<String, Object> dictDyn(TreeMap<String, V> d, Fn1<V, Object> f) {
    if (d == null) return null;
    TreeMap<String, Object> out = dict();
    for (Map.Entry<String, V> e : d.entrySet()) out.put(e.getKey(), f.call(e.getValue()));
    return out;
  }
  /** 不知道具体类型的值（类型变量）装进任意：整数变成小数，列表、字典里的也一样。 */
  static Object toDyn(Object x) {
    if (x instanceof Long n) return (double) (long) n;
    if (x instanceof ArrayList<?> l) {
      ArrayList<Object> out = new ArrayList<>();
      for (Object v : l) out.add(toDyn(v));
      return out;
    }
    if (x instanceof TreeMap<?, ?> d) {
      TreeMap<String, Object> out = dict();
      for (Map.Entry<?, ?> e : d.entrySet()) out.put((String) e.getKey(), toDyn(e.getValue()));
      return out;
    }
    return x;
  }
  static String kind(Object x) {
    if (x == null) return "空";
    if (x instanceof Boolean) return "是否";
    if (x instanceof Number) return "数字";
    if (x instanceof String) return "文字";
    if (x instanceof ArrayList) return "列表";
    if (x instanceof TreeMap) return "字典";
    if (x instanceof Named n) return "「" + n.lcName() + "」";
    if (x instanceof DynFn || x instanceof Fn) return "函数";
    return "「对象」";
  }
  private static <T> T want(String name, Object x) { return fail("这里要" + name + "，拿到的是" + kind(x)); }
  static double asNum(Object x) { return x instanceof Double v ? v : Lc.<Double>want("小数", x); }
  static long asInt(Object x) {
    if (!(x instanceof Double)) return Lc.<Long>want("整数", x);
    double v = (Double) x;
    if (v != Math.floor(v) || Math.abs(v) > MAX) fail("这里要整数，拿到的是 " + fmtNum(v));
    return (long) v;
  }
  static String asText(Object x) { return x instanceof String s ? s : Lc.<String>want("文字", x); }
  static boolean asBool(Object x) { return x instanceof Boolean b ? b : Lc.<Boolean>want("是否", x); }
  static ArrayList<Object> asList(Object x) { return x instanceof ArrayList ? (ArrayList<Object>) x : Lc.<ArrayList<Object>>want("列表", x); }
  static TreeMap<String, Object> asDict(Object x) {
    return x instanceof TreeMap ? (TreeMap<String, Object>) x : Lc.<TreeMap<String, Object>>want("字典", x);
  }
  static <T> T as(Object x, Class<?> c, String name) { return c.isInstance(x) ? (T) x : Lc.<T>want(name, x); }
  static <T> T unsafe(Object x) { return (T) x; }
  static <T> T optFrom(Object x, Fn1<Object, T> f) { return x == null ? null : f.call(x); }
  static <T> ArrayList<T> listFrom(Object x, Fn1<Object, T> f) {
    ArrayList<Object> src = asList(x);
    ArrayList<T> out = new ArrayList<>();
    for (int i = 0; i < src.size(); i++) {
      try {
        out.add(f.call(src.get(i)));
      } catch (LcError e) {
        fail("列表的位置 " + i + "：" + e.getMessage());
      }
    }
    return out;
  }
  static <V> TreeMap<String, V> dictFrom(Object x, Fn1<Object, V> f) {
    TreeMap<String, V> out = dict();
    for (Map.Entry<String, Object> e : asDict(x).entrySet()) {
      try {
        out.put(e.getKey(), f.call(e.getValue()));
      } catch (LcError err) {
        fail("字典的「" + e.getKey() + "」：" + err.getMessage());
      }
    }
    return out;
  }
  /** 任意 → 带类型的函数：原来就是带类型的直接交回去；不是的话用 [adapt] 包一层。 */
  static <T> T asFn(Object x, Fn1<DynFn, T> adapt) {
    if (!(x instanceof DynFn d)) return want("函数", x);
    return d.orig != null ? (T) d.orig : adapt.call(d);
  }

  /** 两个值按内容相不相等（记录、变体按字段；对象看是不是同一个）。 */
  static boolean eq(Object a, Object b) {
    if (a == null || b == null) return a == b;
    if (a instanceof Number x) return b instanceof Number y && x.doubleValue() == y.doubleValue();
    if (a instanceof String || a instanceof Boolean) return a.equals(b);
    if (a instanceof ArrayList<?> x) {
      if (!(b instanceof ArrayList<?> y) || x.size() != y.size()) return false;
      for (int i = 0; i < x.size(); i++) if (!eq(x.get(i), y.get(i))) return false;
      return true;
    }
    if (a instanceof TreeMap<?, ?> x) {
      if (!(b instanceof TreeMap<?, ?> y) || x.size() != y.size()) return false;
      for (Map.Entry<?, ?> e : x.entrySet()) if (!y.containsKey(e.getKey()) || !eq(e.getValue(), y.get(e.getKey()))) return false;
      return true;
    }
    if (a instanceof Rec x) {
      if (!(b instanceof Rec y) || a.getClass() != b.getClass()) return false;
      Object[] p = x.lcFields(), q = y.lcFields();
      for (int i = 0; i < p.length; i++) if (!eq(p[i], q[i])) return false;
      return true;
    }
    if (a instanceof DynFn x && b instanceof DynFn y) return a == b || (x.orig != null && x.orig == y.orig);
    return a == b;
  }
  private static double dnum(String op, Object x) { return x instanceof Double v ? v : Lc.<Double>fail(op + "的两边要数字，拿到的是" + kind(x)); }
  static Object dadd(Object a, Object b) { return dnum("加法", a) + dnum("加法", b); }
  static Object dsub(Object a, Object b) { return dnum("减法", a) - dnum("减法", b); }
  static Object dmul(Object a, Object b) { return dnum("乘法", a) * dnum("乘法", b); }
  static Object ddiv(Object a, Object b) { return fdiv(dnum("除法", a), dnum("除法", b)); }
  static Object dpow(Object a, Object b) { return fpow(dnum("乘方", a), dnum("乘方", b)); }
  static Object didiv(Object a, Object b) { return (double) idiv(asInt(a), asInt(b)); }
  static Object dmod(Object a, Object b) { return (double) imod(asInt(a), asInt(b)); }
  static long dcmp(Object a, Object b) {
    if (a instanceof Double x && b instanceof Double y) return x < y ? -1 : x > y ? 1 : 0;
    if (a instanceof String x && b instanceof String y) return cmpText(x, y);
    return fail("比大小的两边要都是数字或者都是文字，拿到的是" + kind(a) + "和" + kind(b));
  }
  static Object dynGet(Object x, Object k) {
    if (x instanceof ArrayList) return at(asList(x), asInt(k));
    if (x instanceof TreeMap) return asDict(x).get(asText(k));
    return fail("这里要列表或字典，拿到的是" + kind(x));
  }
  static void dynSet(Object x, Object k, Object v) {
    if (x instanceof ArrayList) setAt(asList(x), asInt(k), v);
    else if (x instanceof TreeMap) asDict(x).put(asText(k), v);
    else fail("这里要列表或字典，拿到的是" + kind(x));
  }
  static void dynPush(Object x, Object v) { asList(x).add(v); }
  static Object dynPop(Object x) { return pop(asList(x)); }
  static void dynRemove(Object x, Object k) { asDict(x).remove(asText(k)); }
  static Object dynOrElse(Object x, Object d) { return x == null ? d : x; }
  static long dynSize(Object x) {
    if (x instanceof String s) return textLen(s);
    if (x instanceof ArrayList<?> l) return l.size();
    if (x instanceof TreeMap<?, ?> d) return d.size();
    return fail("这里要文字、列表或字典，拿到的是" + kind(x));
  }
  static Object dynCall(Object f, Object... args) {
    if (!(f instanceof DynFn d)) return want("函数", f);
    if (d.n != args.length) fail("这个函数要 " + d.n + " 个参数，给了 " + args.length + " 个");
    return d.f.call(args);
  }

  // —— JSON、写成文字 ——
  static String jstr(String s) {
    StringBuilder b = new StringBuilder("\"");
    for (int i = 0; i < s.length(); i++) {
      char c = s.charAt(i);
      switch (c) {
        case '"' -> b.append("\\\"");
        case '\\' -> b.append("\\\\");
        case '\b' -> b.append("\\b");
        case '\f' -> b.append("\\f");
        case '\n' -> b.append("\\n");
        case '\r' -> b.append("\\r");
        case '\t' -> b.append("\\t");
        default -> {
          if (c < 0x20) b.append(String.format("\\u%04x", (int) c));
          else if (Character.isSurrogate(c) && !(Character.isHighSurrogate(c) && i + 1 < s.length() && Character.isLowSurrogate(s.charAt(i + 1)))
              && !(Character.isLowSurrogate(c) && i > 0 && Character.isHighSurrogate(s.charAt(i - 1)))) b.append('\ufffd');
          else b.append(c);
        }
      }
    }
    return b.append('"').toString();
  }
  static String toJson(Object x) {
    if (x == null) return "null";
    if (x instanceof Boolean v) return boolText(v);
    if (x instanceof Long n) return itext(n);
    if (x instanceof Double v) return Double.isNaN(v) || Double.isInfinite(v) ? "null" : fmtNum(v);
    if (x instanceof String s) return jstr(s);
    if (x instanceof ArrayList<?> l) {
      StringBuilder b = new StringBuilder("[");
      for (int i = 0; i < l.size(); i++) b.append(i > 0 ? "," : "").append(toJson(l.get(i)));
      return b.append("]").toString();
    }
    if (x instanceof TreeMap<?, ?> d) {
      StringBuilder b = new StringBuilder("{");
      for (Map.Entry<?, ?> e : d.entrySet()) b.append(b.length() > 1 ? "," : "").append(jstr((String) e.getKey())).append(":").append(toJson(e.getValue()));
      return b.append("}").toString();
    }
    if (x instanceof Rec r) return r.lcJson();
    if (x instanceof Enum && x instanceof Named n) return jstr(n.lcName());
    return "null";
  }
  static String dtext(Object x) {
    if (x == null) return "";
    if (x instanceof Boolean v) return boolText(v);
    if (x instanceof Long n) return itext(n);
    if (x instanceof Double v) return fmtNum(v);
    if (x instanceof String s) return s;
    if (x instanceof ArrayList || x instanceof TreeMap || x instanceof Rec) return toJson(x);
    if (x instanceof Enum && x instanceof Named n) return n.lcName();
    if (x instanceof Named n) return "[" + n.lcName() + "]";
    if (x instanceof DynFn || x instanceof Fn) return "[函数]";
    return "[对象]";
  }

  private static final class JsonIn {
    final String s;
    int i = 0;
    JsonIn(String s) { this.s = s; }
    RuntimeException bad() { return new LcError("这段文字不是 JSON"); }
    void ws() { while (i < s.length() && " \t\n\r".indexOf(s.charAt(i)) >= 0) i++; }
    boolean eat(String w) {
      if (!s.startsWith(w, i)) return false;
      i += w.length();
      return true;
    }
    Object value(int depth) {
      ws();
      if (i >= s.length() || depth > 2000) throw bad();
      char c = s.charAt(i);
      if (c == '{') {
        i++;
        TreeMap<String, Object> d = dict();
        ws();
        if (eat("}")) return d;
        while (true) {
          ws();
          if (i >= s.length() || s.charAt(i) != '"') throw bad();
          String k = text();
          ws();
          if (!eat(":")) throw bad();
          d.put(k, value(depth + 1));
          ws();
          if (eat("}")) return d;
          if (!eat(",")) throw bad();
        }
      }
      if (c == '[') {
        i++;
        ArrayList<Object> l = new ArrayList<>();
        ws();
        if (eat("]")) return l;
        while (true) {
          l.add(value(depth + 1));
          ws();
          if (eat("]")) return l;
          if (!eat(",")) throw bad();
        }
      }
      if (c == '"') return text();
      if (eat("true")) return true;
      if (eat("false")) return false;
      if (eat("null")) return null;
      int from = i;
      while (i < s.length() && "+-0123456789.eE".indexOf(s.charAt(i)) >= 0) i++;
      String n = s.substring(from, i);
      if (!n.matches("-?(0|[1-9][0-9]*)(\\.[0-9]+)?([eE][+-]?[0-9]+)?")) throw bad();
      return Double.parseDouble(n);
    }
    String text() {
      StringBuilder b = new StringBuilder();
      i++;
      while (true) {
        if (i >= s.length()) throw bad();
        char c = s.charAt(i++);
        if (c == '"') return b.toString();
        if (c < 0x20) throw bad();
        if (c != '\\') {
          b.append(c);
          continue;
        }
        if (i >= s.length()) throw bad();
        char e = s.charAt(i++);
        int at = "\"\\/bfnrt".indexOf(e);
        if (at >= 0) {
          b.append("\"\\/\b\f\n\r\t".charAt(at));
        } else if (e == 'u' && i + 4 <= s.length() && s.substring(i, i + 4).matches("[0-9a-fA-F]{4}")) {
          b.append((char) Integer.parseInt(s.substring(i, i + 4), 16));
          i += 4;
        } else {
          throw bad();
        }
      }
    }
  }
  static Object fromJson(String s) {
    JsonIn in = new JsonIn(s);
    Object v = in.value(0);
    in.ws();
    if (in.i != s.length()) throw in.bad();
    return v;
  }

  // —— 出错、输出 ——
  private static final ArrayList<String> out = new ArrayList<>();
  static void log(String s) { out.add(s); }
  static void run(Act0 main) {
    try {
      main.call();
    } catch (LcError e) {
      out.add("出错：" + e.getMessage());
    }
    byte[] bytes = (String.join("\n", out) + "\n").getBytes(StandardCharsets.UTF_8);
    System.out.write(bytes, 0, bytes.length);
    System.out.flush();
  }
}
''';
