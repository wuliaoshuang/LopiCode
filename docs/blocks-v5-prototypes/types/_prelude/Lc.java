// 类型原型用的“小库”（Java 版）。只为验证类型设计，不是产品代码。
import java.math.BigDecimal;
import java.math.MathContext;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.TreeMap;

final class Lc {
  static final long MAX = 9007199254740991L;

  static final class LcError extends RuntimeException {
    private static final long serialVersionUID = 1L;
    LcError(String m) { super(m); }
  }

  static <T> T fail(String m) { throw new LcError(m); }

  // 函数类型：Java 没有“(A,B)→R”这种写法，用小库里这一组接口
  interface Fn0<R> { R call(); }
  interface Fn1<A, R> { R call(A a); }
  interface Fn2<A, B, R> { R call(A a, B b); }
  interface Act0 { void call(); }
  interface Act1<A> { void call(A a); }
  interface Act2<A, B> { void call(A a, B b); }

  /** 被匿名函数改写的局部变量要装进这个盒子（Java 的匿名函数只能读不能改外面的局部变量）。 */
  static final class Ref<T> {
    T v;
    Ref(T v) { this.v = v; }
  }

  static String fmtNum(double v) {
    if (Double.isNaN(v)) return "不是数";
    if (Double.isInfinite(v)) return v > 0 ? "无穷大" : "-无穷大";
    if (v == 0) return "0";
    if (v == Math.floor(v) && Math.abs(v) <= MAX) return Long.toString((long) v);
    BigDecimal r = new BigDecimal(Math.abs(v)).round(new MathContext(12, RoundingMode.HALF_UP));
    String digits = r.unscaledValue().toString();
    int e = digits.length() - 1 - r.scale();
    digits = digits.replaceAll("0+$", "");
    String minus = v < 0 ? "-" : "";
    if (e >= 15 || e < -7) return minus + digits.charAt(0) + (digits.length() > 1 ? "." + digits.substring(1) : "") + "e" + e;
    if (e >= digits.length() - 1) return minus + digits + "0".repeat(e - digits.length() + 1);
    if (e >= 0) return minus + digits.substring(0, e + 1) + "." + digits.substring(e + 1);
    return minus + "0." + "0".repeat(-e - 1) + digits;
  }

  static String intText(long n) { return Long.toString(n); }

  private static long chk(long r) { return r > MAX || r < -MAX ? Lc.<Long>fail("整数超出范围") : r; }
  static long iadd(long a, long b) { return chk(a + b); }
  static long isub(long a, long b) { return chk(a - b); }
  static long imul(long a, long b) {
    if (Math.abs((double) a * (double) b) > 2.0 * MAX) fail("整数超出范围");
    return chk(a * b);
  }
  static long idiv(long a, long b) { return b == 0 ? Lc.<Long>fail("除以 0") : a / b; }
  static long imod(long a, long b) { return b == 0 ? Lc.<Long>fail("除以 0") : a % b; }
  static double fdiv(double a, double b) { return b == 0 ? Lc.<Double>fail("除以 0") : a / b; }
  static long ftoi(double x) {
    double t = x < 0 ? Math.ceil(x) : Math.floor(x);
    if (Double.isNaN(x) || Double.isInfinite(x) || Math.abs(t) > MAX) fail("这个小数变不成整数：" + fmtNum(x));
    return (long) t;
  }

  static long textLen(String s) { return s.codePointCount(0, s.length()); }

  /** 文字按码点比（Java 自己的 compareTo 按 UTF-16 比，表情符号的顺序会和别的语言不一样）。 */
  static int cmpText(String a, String b) {
    int i = 0, j = 0;
    while (i < a.length() && j < b.length()) {
      int x = a.codePointAt(i), y = b.codePointAt(j);
      if (x != y) return x < y ? -1 : 1;
      i += Character.charCount(x);
      j += Character.charCount(y);
    }
    return i < a.length() ? 1 : j < b.length() ? -1 : 0;
  }
  @SuppressWarnings("unchecked")
  static <T extends Comparable<T>> long cmp(T a, T b) {
    if (a instanceof String s) return cmpText(s, (String) b);
    return Integer.signum(a.compareTo(b));
  }

  private static String rangeMsg(long i, int n) { return "位置 " + i + " 超出了列表的范围（共 " + n + " 项）"; }
  static <T> T at(ArrayList<T> xs, long i) { return i >= 0 && i < xs.size() ? xs.get((int) i) : fail(rangeMsg(i, xs.size())); }
  static <T> void setAt(ArrayList<T> xs, long i, T v) {
    if (i >= 0 && i < xs.size()) xs.set((int) i, v); else fail(rangeMsg(i, xs.size()));
  }
  @SafeVarargs
  static <T> ArrayList<T> list(T... items) {
    ArrayList<T> out = new ArrayList<>();
    for (T x : items) out.add(x);
    return out;
  }
  static <T, U> ArrayList<U> map(ArrayList<T> xs, Fn1<T, U> f) {
    ArrayList<U> out = new ArrayList<>();
    for (T x : xs) out.add(f.call(x));
    return out;
  }
  static <T> ArrayList<T> filter(ArrayList<T> xs, Fn1<T, Boolean> f) {
    ArrayList<T> out = new ArrayList<>();
    for (T x : xs) if (f.call(x)) out.add(x);
    return out;
  }
  static <T, A> A reduce(ArrayList<T> xs, A init, Fn2<A, T, A> f) {
    A acc = init;
    for (T x : xs) acc = f.call(acc, x);
    return acc;
  }

  static ArrayList<String> split(String s, String sep) {
    ArrayList<String> out = new ArrayList<>();
    int from = 0;
    while (true) {
      int i = s.indexOf(sep, from);
      if (i < 0) break;
      out.add(s.substring(from, i));
      from = i + sep.length();
    }
    out.add(s.substring(from));
    return out;
  }
  static String substr(String s, long from, long to) {
    return s.substring(s.offsetByCodePoints(0, (int) from), s.offsetByCodePoints(0, (int) to));
  }
  static Long parseInt(String s) {
    if (!s.matches("-?[0-9]+")) return null;
    try {
      long n = Long.parseLong(s);
      return n > MAX || n < -MAX ? null : n;
    } catch (NumberFormatException e) {
      return null;
    }
  }

  /** 确定类型的列表 / 字典装进“任意”：拍一份快照（第二轮定的规矩）。 */
  static <T> ArrayList<Object> dynList(ArrayList<T> xs, Fn1<T, Object> f) {
    ArrayList<Object> out = new ArrayList<>();
    for (T v : xs) out.add(f.call(v));
    return out;
  }
  static <V> TreeMap<String, Object> dynDict(TreeMap<String, V> d, Fn1<V, Object> f) {
    TreeMap<String, Object> out = dict();
    for (var e : d.entrySet()) out.put(e.getKey(), f.call(e.getValue()));
    return out;
  }
  /** “任意”取回成 列表〈T〉：逐项检查，得到一份新的。 */
  static <T> ArrayList<T> listFrom(Object x, Fn1<Object, T> f) {
    ArrayList<T> out = new ArrayList<>();
    long i = 0;
    for (Object v : asList(x)) {
      try { out.add(f.call(v)); } catch (LcError e) { fail("列表的位置 " + i + "：" + e.getMessage()); }
      i++;
    }
    return out;
  }

  /** 字典：按码点排好序的 TreeMap。 */
  static <V> TreeMap<String, V> dict() { return new TreeMap<>(Lc::cmpText); }
  static <T> T must(T x) { return x == null ? fail("这里的值是空，不能直接用") : x; }
  static <T> T or(T x, T def) { return x == null ? def : x; }

  // —— 任意 ——
  static String kind(Object x) {
    if (x == null) return "空";
    if (x instanceof Boolean) return "是否";
    if (x instanceof Double) return "数字";
    if (x instanceof String) return "文字";
    if (x instanceof ArrayList) return "列表";
    if (x instanceof TreeMap) return "字典";
    return "对象";
  }
  private static <T> T want(String name, Object x) { return fail("这里要" + name + "，拿到的是" + kind(x)); }
  static double asNum(Object x) { return x instanceof Double d ? d : Lc.<Double>want("小数", x); }
  static long asInt(Object x) {
    if (!(x instanceof Double d)) return Lc.<Long>want("整数", x);
    if (d != Math.floor(d) || Math.abs(d) > MAX) fail("这里要整数，拿到的是 " + fmtNum(d));
    return (long) (double) d;
  }
  static String asText(Object x) { return x instanceof String s ? s : want("文字", x); }
  static boolean asBool(Object x) { return x instanceof Boolean b ? b : Lc.<Boolean>want("是否", x); }
  @SuppressWarnings("unchecked")
  static ArrayList<Object> asList(Object x) { return x instanceof ArrayList ? (ArrayList<Object>) x : want("列表", x); }
  @SuppressWarnings("unchecked")
  static TreeMap<String, Object> asDict(Object x) { return x instanceof TreeMap ? (TreeMap<String, Object>) x : want("字典", x); }
  private static double dnum(String op, Object x) { return x instanceof Double d ? d : Lc.<Double>fail(op + "的两边要数字，拿到的是" + kind(x)); }
  static Object dadd(Object a, Object b) { return dnum("加法", a) + dnum("加法", b); }
  static Object dsub(Object a, Object b) { return dnum("减法", a) - dnum("减法", b); }
  static Object dmul(Object a, Object b) { return dnum("乘法", a) * dnum("乘法", b); }
  static Object ddiv(Object a, Object b) { return fdiv(dnum("除法", a), dnum("除法", b)); }
  static Object didiv(Object a, Object b) { return (double) idiv(asInt(a), asInt(b)); }
  static Object dimod(Object a, Object b) { return (double) imod(asInt(a), asInt(b)); }
  static String djson(Object x) { return x == null ? "null" : x instanceof String s ? "\"" + s + "\"" : dtext(x); }
  static String dtext(Object x) {
    if (x == null) return "";
    if (x instanceof Boolean b) return boolText(b);
    if (x instanceof Double d) return fmtNum(d);
    if (x instanceof String s) return s;
    if (x instanceof ArrayList<?> l) {
      StringBuilder sb = new StringBuilder("[");
      for (int i = 0; i < l.size(); i++) sb.append(i > 0 ? "," : "").append(djson(l.get(i)));
      return sb.append("]").toString();
    }
    if (x instanceof TreeMap<?, ?> m) {
      StringBuilder sb = new StringBuilder("{");
      boolean first = true;
      for (var e : m.entrySet()) {
        sb.append(first ? "" : ",").append("\"").append(e.getKey()).append("\":").append(djson(e.getValue()));
        first = false;
      }
      return sb.append("}").toString();
    }
    return "[" + kind(x) + "]";
  }
  static String boolText(boolean b) { return b ? "true" : "false"; }

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
