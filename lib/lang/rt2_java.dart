/// 规矩版本 2 的小库·Java（`Lc.java`）·上半：函数类型、数字、文字、列表、字典。下半在 rt2_java_dyn.dart。
/// 规矩见 docs/blocks-v5-parts/B-type-system.md 第 2、5、7、8、11 节。
///
/// 值在 Java 里的样子（生成器照 7.1 的表）：整数＝long（可空、泛型里是 Long）；小数＝double / Double；文字＝String；
/// 是否＝boolean / Boolean；列表〈T〉＝`ArrayList<T>`；字典〈V〉＝按码点排序的 `TreeMap<String, V>`；记录＝record；枚举＝enum；
/// 变体＝接口＋每种情况一个 record；类＝class；函数＝Lc.Fn0…Fn4 / Lc.Act0…Act4；
/// “任意”＝Object，里面的数字一律是 Double（取回成整数时检查）。
library;

const String kRt2JavaHead = r'''
// LopiCode 积木的小库（Java，严格规矩）。由 LopiCode 生成，别手改。
import java.math.BigDecimal;
import java.math.MathContext;
import java.math.RoundingMode;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Map;
import java.util.TreeMap;

@SuppressWarnings({"unchecked", "rawtypes"})
final class Lc {
  private Lc() {}

  static final long MAX = 9007199254740991L;

  static final class LcError extends RuntimeException {
    private static final long serialVersionUID = 1L;
    /** 错误对象（小库自己报的错没有，接住的时候才按种类造）。 */
    transient Object obj;
    LcError(String m) { super(m); }
    LcError(String m, Object obj) { super(m); this.obj = obj; }
  }

  private static final String[][] ERR_KINDS = {{"除以 0", "数值不对"}, {"整数超出范围", "数值不对"}, {"变不成整数", "数值不对"}, {"超出了", "找不到"}, {"拿到的是", "类型不对"}, {"值是空", "类型不对"}, {"还没做完", "超时"}, {"被取消了", "取消了"}};
  /** 小库自己报的错归到哪一种。 */
  static String errKind(String m) {
    for (String[] p : ERR_KINDS) if (m.contains(p[0])) return p[1];
    return "错误";
  }

  static <T> T fail(String m) { throw new LcError(m); }

  // 函数类型：Java 没有“(A, B) → R”这种写法，用这一组接口。
  interface Fn {}
  interface Fn0<R> extends Fn { R call(); }
  interface Fn1<A, R> extends Fn { R call(A a); }
  interface Fn2<A, B, R> extends Fn { R call(A a, B b); }
  interface Fn3<A, B, C, R> extends Fn { R call(A a, B b, C c); }
  interface Fn4<A, B, C, D, R> extends Fn { R call(A a, B b, C c, D d); }
  interface Act0 extends Fn { void call(); }
  interface Act1<A> extends Fn { void call(A a); }
  interface Act2<A, B> extends Fn { void call(A a, B b); }
  interface Act3<A, B, C> extends Fn { void call(A a, B b, C c); }
  interface Act4<A, B, C, D> extends Fn { void call(A a, B b, C c, D d); }

  /** 被匿名函数用到的局部变量装进这个盒子（Java 的匿名函数不能改外面的局部变量）。 */
  static final class Ref<T> {
    T v;
    Ref(T v) { this.v = v; }
  }

  interface Named { String lcName(); }
  /** 记录、变体的一种情况。 */
  interface Rec extends Named {
    Object[] lcFields();
    String lcJson();
  }
  /** 类的对象。 */
  interface Obj extends Named {}

  static void drop(Object x) {}
  static <T> T second(Object a, T b) { return b; }

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
  static String itext(long n) { return Long.toString(n); }
  static String boolText(boolean b) { return b ? "true" : "false"; }

  // —— 整数、小数 ——
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
  static double fpow(double a, double b) { return Math.pow(a, b); }
  static long toInt(double x) {
    double t = x < 0 ? Math.ceil(x) : Math.floor(x);
    if (Double.isNaN(x) || Double.isInfinite(x) || Math.abs(t) > MAX) fail("这个小数变不成整数：" + fmtNum(x));
    return (long) t;
  }
  static long floor(double x) { return toInt(Math.floor(x)); }
  static long ceil(double x) { return toInt(Math.ceil(x)); }
  static long round(double x) {
    if (Double.isNaN(x) || Double.isInfinite(x)) return toInt(x);
    double t = x < 0 ? Math.ceil(x) : Math.floor(x);
    return toInt(Math.abs(x - t) >= 0.5 ? t + (x < 0 ? -1 : 1) : t);
  }
  static double sqrt(double x) { return Math.sqrt(x); }
  static double now() { return (double) System.currentTimeMillis(); }
  static long steps(long a, long b, long s) {
    if (s == 0 || (b > a && s < 0) || (b < a && s > 0)) return 0;
    return (b - a) / s + 1;
  }
  static long fsteps(double a, double b, double s) {
    if (s == 0) return 0;
    double d = (b - a) / s;
    if (!(d >= 0)) return 0;
    double n = Math.floor(d + 1e-9) + 1;
    return n >= MAX ? MAX : (long) n;
  }

  // —— 文字（按码点） ——
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
  static long cmp(Object a, Object b) {
    if (a instanceof String s) return cmpText(s, (String) b);
    double x = ((Number) a).doubleValue(), y = ((Number) b).doubleValue();
    return x < y ? -1 : x > y ? 1 : 0;
  }
  private static int clamp(long i, int n) { return i < 0 ? 0 : i > n ? n : (int) i; }
  static String substring(String s, long from, long to) {
    int n = (int) textLen(s), a = clamp(from, n), b = clamp(to, n);
    return a >= b ? "" : s.substring(s.offsetByCodePoints(0, a), s.offsetByCodePoints(0, b));
  }
  static String charAt(String s, long i) {
    long n = textLen(s);
    if (i < 0 || i >= n) fail("位置 " + i + " 超出了文字的范围（共 " + n + " 个字）");
    int at = s.offsetByCodePoints(0, (int) i);
    return new String(Character.toChars(s.codePointAt(at)));
  }
  static ArrayList<Long> codePoints(String s) {
    ArrayList<Long> out = new ArrayList<>();
    s.codePoints().forEach(c -> out.add((long) c));
    return out;
  }
  static ArrayList<String> split(String s, String sep) {
    ArrayList<String> out = new ArrayList<>();
    if (sep.isEmpty()) {
      s.codePoints().forEach(c -> out.add(new String(Character.toChars(c))));
      return out;
    }
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
  static boolean startsWith(String s, String p) { return s.startsWith(p); }
  static boolean endsWith(String s, String p) { return s.endsWith(p); }
  static boolean contains(String s, String p) { return s.contains(p); }
  static long indexOf(String s, String p) {
    int at = s.indexOf(p);
    return at < 0 ? -1 : s.codePointCount(0, at);
  }
  static String replace(String s, String from, String to) { return from.isEmpty() ? s : s.replace(from, to); }
  private static boolean isWs(int c) {
    return c == '\t' || c == '\n' || c == 0x0b || c == '\f' || c == '\r' || c == ' ' || c == 0xa0 || c == 0x1680 || (c >= 0x2000 && c <= 0x200a)
        || c == 0x2028 || c == 0x2029 || c == 0x202f || c == 0x205f || c == 0x3000 || c == 0xfeff;
  }
  static String trim(String s) {
    int a = 0, b = s.length();
    while (a < b && isWs(s.charAt(a))) a++;
    while (b > a && isWs(s.charAt(b - 1))) b--;
    return s.substring(a, b);
  }
  static String upper(String s) { return s.toUpperCase(java.util.Locale.ROOT); }
  static String lower(String s) { return s.toLowerCase(java.util.Locale.ROOT); }
  static String repeatText(String s, long n) { return n <= 0 ? "" : s.repeat((int) n); }
  static Long parseInt(String s) {
    if (!s.matches("-?[0-9]+")) return null;
    try {
      long n = Long.parseLong(s);
      return n > MAX || n < -MAX ? null : n;
    } catch (NumberFormatException e) {
      return null;
    }
  }

  // —— 列表、字典 ——
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
  static <T> ArrayList<T> items(ArrayList<T> xs) { return new ArrayList<>(xs); }
  static <T> T pop(ArrayList<T> xs) { return xs.isEmpty() ? null : xs.remove(xs.size() - 1); }
  static long len(java.util.Collection<?> xs) { return xs.size(); }
  static long len(Map<?, ?> d) { return d.size(); }
  static <V> TreeMap<String, V> dict() { return new TreeMap<>(Lc::cmpText); }
  static <V> TreeMap<String, V> put(TreeMap<String, V> d, String k, V v) {
    d.put(k, v);
    return d;
  }
  static <V> ArrayList<String> keys(TreeMap<String, V> d) { return new ArrayList<>(d.keySet()); }
  static <V> ArrayList<V> dictValues(TreeMap<String, V> d) { return new ArrayList<>(d.values()); }
  static <T> T must(T x) { return x == null ? fail("这里的值是空，不能直接用") : x; }
  static <T> T orElse(T x, Fn0<T> def) { return x == null ? def.call() : x; }
  static Double widenOpt(Long x) { return x == null ? null : (double) (long) x; }
  static <T, U> ArrayList<U> listMap(ArrayList<T> xs, Fn1<T, U> f) {
    ArrayList<U> out = new ArrayList<>();
    for (T x : items(xs)) out.add(f.call(x));
    return out;
  }
  static <T> ArrayList<T> listFilter(ArrayList<T> xs, Fn1<T, Boolean> f) {
    ArrayList<T> out = new ArrayList<>();
    for (T x : items(xs)) if (f.call(x)) out.add(x);
    return out;
  }
  static <T, A> A listReduce(ArrayList<T> xs, Fn2<A, T, A> f, A init) {
    A acc = init;
    for (T x : items(xs)) acc = f.call(acc, x);
    return acc;
  }
  static <T> T listFind(ArrayList<T> xs, Fn1<T, Boolean> f) {
    for (T x : items(xs)) if (f.call(x)) return x;
    return null;
  }
  static <T> boolean listEvery(ArrayList<T> xs, Fn1<T, Boolean> f) {
    for (T x : items(xs)) if (!f.call(x)) return false;
    return true;
  }
  static <T> boolean listSome(ArrayList<T> xs, Fn1<T, Boolean> f) {
    for (T x : items(xs)) if (f.call(x)) return true;
    return false;
  }
  static <T> void listEach(ArrayList<T> xs, Act1<T> f) { for (T x : items(xs)) f.call(x); }
  static String listJoin(ArrayList<String> xs, String sep) { return String.join(sep, xs); }
  static <T> ArrayList<T> listReverse(ArrayList<T> xs) {
    ArrayList<T> out = new ArrayList<>(xs);
    java.util.Collections.reverse(out);
    return out;
  }
  static <T> ArrayList<T> listConcat(ArrayList<T> a, ArrayList<T> b) {
    ArrayList<T> out = new ArrayList<>(a);
    out.addAll(b);
    return out;
  }
  static <T> ArrayList<T> listSlice(ArrayList<T> xs, long from, long to) {
    int a = clamp(from, xs.size()), b = clamp(to, xs.size());
    return a >= b ? new ArrayList<>() : new ArrayList<>(xs.subList(a, b));
  }
  static <T> long listIndexOf(ArrayList<T> xs, T v) {
    for (int i = 0; i < xs.size(); i++) if (eq(xs.get(i), v)) return i;
    return -1;
  }
  static <T> boolean listContains(ArrayList<T> xs, T v) { return listIndexOf(xs, v) >= 0; }
  static ArrayList<Long> range(long a, long b, long s) {
    ArrayList<Long> out = new ArrayList<>();
    for (long k = 0, n = Math.min(steps(a, b, s), 10000); k < n; k++) out.add(a + k * s);
    return out;
  }
  // —— 后端积木里早就有的那几个（严格规矩下的说法见 rt_v2.dart）。“任意”里的数字是 Double。 ——
  private static double numArg(String name, Object x) { return x instanceof Double v ? v : Lc.<Double>fail("「" + name + "」要数字，拿到的是" + kind(x)); }
  static long abs(long x) { return Math.abs(x); }
  static double abs(double x) { return Math.abs(x); }
  static Object abs(Object x) { return Math.abs(numArg("绝对值", x)); }
  static long max(long a, long b) { return a >= b ? a : b; }
  static double max(double a, double b) { return a >= b ? a : b; }
  static Object max(Object a, Object b) { return numArg("较大的", a) >= numArg("较大的", b) ? a : b; }
  static long min(long a, long b) { return a <= b ? a : b; }
  static double min(double a, double b) { return a <= b ? a : b; }
  static Object min(Object a, Object b) { return numArg("较小的", a) <= numArg("较小的", b) ? a : b; }
  static long random(long a, long b) {
    long lo = Math.min(a, b), hi = Math.max(a, b);
    return lo + (long) Math.floor(Math.random() * (hi - lo + 1));
  }
  static <T> T copy(T x) {
    if (x instanceof ArrayList<?> xs) {
      ArrayList<Object> out = new ArrayList<>();
      for (Object v : xs) out.add(copy(v));
      return (T) out;
    }
    if (x instanceof TreeMap<?, ?> d) {
      TreeMap<String, Object> out = dict();
      for (Map.Entry<?, ?> e : d.entrySet()) out.put((String) e.getKey(), copy(e.getValue()));
      return (T) out;
    }
    return x;
  }
  static <V> String template(String s, TreeMap<String, V> d) {
    StringBuilder out = new StringBuilder();
    int i = 0;
    while (i < s.length()) {
      int open = s.indexOf('{', i);
      if (open < 0) break;
      int close = open + 1;
      while (close < s.length() && s.charAt(close) != '}' && s.charAt(close) != '{') close++;
      if (close >= s.length() || s.charAt(close) == '{') {
        out.append(s, i, close);
        i = close;
        continue;
      }
      String key = s.substring(open + 1, close);
      out.append(s, i, open).append(d.containsKey(key) ? dtext(d.get(key)) : s.substring(open, close + 1));
      i = close + 1;
    }
    return out.append(s.substring(i)).toString();
  }
  static boolean toBool(Object x) {
    return !(x == null || Boolean.FALSE.equals(x) || "".equals(x) || (x instanceof Number n && n.doubleValue() == 0));
  }
  static <T> void listInsert(ArrayList<T> xs, long i, T v) {
    if (i < 0 || i > xs.size()) fail(rangeMsg(i, xs.size()));
    xs.add((int) i, v);
  }
  static <T> T listRemove(ArrayList<T> xs, long i) { return i >= 0 && i < xs.size() ? xs.remove((int) i) : fail(rangeMsg(i, xs.size())); }
  static <T> ArrayList<T> listSort(ArrayList<T> xs) {
    boolean nums = true, texts = true;
    for (T v : xs) {
      nums = nums && v instanceof Number;
      texts = texts && v instanceof String;
    }
    if (!nums && !texts) fail("排序要全是数字或者全是文字的列表，拿到的是混着的");
    ArrayList<T> out = new ArrayList<>(xs);
    if (nums) out.sort((a, b) -> Double.compare(((Number) a).doubleValue(), ((Number) b).doubleValue()));
    else out.sort((a, b) -> cmpText((String) a, (String) b));
    return out;
  }
  static <V> ArrayList<ArrayList<Object>> dictPairs(TreeMap<String, V> d) {
    ArrayList<ArrayList<Object>> out = new ArrayList<>();
    for (Map.Entry<String, V> e : d.entrySet()) {
      ArrayList<Object> pair = new ArrayList<>();
      pair.add(e.getKey());
      pair.add(toDyn(e.getValue()));
      out.add(pair);
    }
    return out;
  }
''';
