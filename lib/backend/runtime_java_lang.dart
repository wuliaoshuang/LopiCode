/// Java 的语言核心小库（生成的工程里的 `LcLang.java`）：积木第 4 版新加的操作。只有用到新积木的工程才带这个文件。
///
/// 函数表和规矩见 lib/lang/rt.dart 的 `kLangRtFns`；改这里的行为要同时改别的语言的
/// （`test/lang_conformance_test.dart` 让各语言跑同一批程序、比对输出是否逐字节相同）。
library;

const String kJavaLangRuntimeSource = r'''
// LopiCode 语言核心小库（Java）：积木第 4 版新加的操作——类型、数学、文字、列表、字典、JSON、数列。
// 每份生成的工程都一样，不用改。规矩：位置从 0 数；文字按 Unicode 码点算；读不到得空；写到不存在的位置抛错。
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ThreadLocalRandom;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class LcLang {
    private LcLang() {}

    static final int RANGE_LIMIT = 10000; // “数列”“重复文字”最多这么多项
    static final int COUNT_LIMIT = 2147483647; // “从…数到…”最多数这么多遍

    static final String E_NOT_LIST = "这不是列表，改不了";
    static final String E_NOT_DICT = "这不是字典，改不了";
    static final String E_NO_ITEM = "列表里没有这个位置";
    static final String E_NOT_INDEXABLE = "这个值不能按位置或键来改";

    private static final Pattern HOLE = Pattern.compile("\\{([^{}]*)\\}");

    /** 积木运行时出的错（比如往列表里不存在的位置写）。 */
    public static final class LcError extends RuntimeException {
        private static final long serialVersionUID = 1L;

        LcError(String message) {
            super(message);
        }
    }

    /** 去掉“负零”（各语言写出来不一样）。 */
    static double pz(double n) {
        return n == 0 ? 0 : n;
    }

    /** 位置：数字化后去掉小数部分（大得离谱的会夹在 int 的范围里）。 */
    static int index(Object i) {
        return (int) Lc.toNum(i);
    }

    static int clamp(int n, int lo, int hi) {
        return n < lo ? lo : n > hi ? hi : n;
    }

    /** 列表里的那一串值（不复制）；不是列表就是空的。 */
    static List<Object> list(Object x) {
        List<Object> list = Lc.asList(x);
        return list == null ? new ArrayList<>() : list;
    }

    static List<Object> mustList(Object x) {
        List<Object> list = Lc.asList(x);
        if (list == null) throw new LcError(E_NOT_LIST);
        return list;
    }

    static Map<String, Object> mustDict(Object x) {
        Map<String, Object> dict = Lc.asObj(x);
        if (dict == null) throw new LcError(E_NOT_DICT);
        return dict;
    }

    static List<String> keys(Object d) {
        Map<String, Object> dict = Lc.asObj(d);
        List<String> keys = dict == null ? new ArrayList<>() : new ArrayList<>(dict.keySet());
        keys.sort(LcJson::compareKeys);
        return keys;
    }

    // —— 类型 ——

    public static boolean isType(Object x, Object name) {
        String k = Lc.kind(x);
        String want = k.equals("num") ? "number" : k.equals("obj") ? "dict" : k;
        return want.equals(Lc.toText(name));
    }

    public static double toNumber(Object x) {
        return Lc.toNum(x);
    }

    public static String toText(Object x) {
        return Lc.toText(x);
    }

    public static boolean toBool(Object x) {
        return Lc.truthy(x);
    }

    public static Object copy(Object x) {
        List<Object> list = Lc.asList(x);
        if (list != null) {
            List<Object> out = new ArrayList<>(list.size());
            for (Object v : list) out.add(copy(v));
            return out;
        }
        Map<String, Object> dict = Lc.asObj(x);
        if (dict != null) {
            Map<String, Object> out = new HashMap<>();
            for (Map.Entry<String, Object> e : dict.entrySet()) out.put(e.getKey(), copy(e.getValue()));
            return out;
        }
        return x;
    }

    // —— 数学 ——

    public static double pow(Object a, Object b) {
        return pz(Lc.fin(Math.pow(Lc.toNum(a), Lc.toNum(b))));
    }

    public static double round(Object x) {
        double n = Lc.toNum(x);
        double t = n < 0 ? Math.ceil(n) : Math.floor(n);
        return pz(Math.abs(n - t) >= 0.5 ? t + (n < 0 ? -1 : 1) : t);
    }

    public static double floor(Object x) {
        return pz(Math.floor(Lc.toNum(x)));
    }

    public static double ceil(Object x) {
        return pz(Math.ceil(Lc.toNum(x)));
    }

    public static double abs(Object x) {
        return Math.abs(Lc.toNum(x));
    }

    public static double sqrt(Object x) {
        double n = Lc.toNum(x);
        return n < 0 ? 0 : Math.sqrt(n);
    }

    public static double max(Object a, Object b) {
        double x = Lc.toNum(a);
        double y = Lc.toNum(b);
        return x >= y ? x : y;
    }

    public static double min(Object a, Object b) {
        double x = Lc.toNum(a);
        double y = Lc.toNum(b);
        return x <= y ? x : y;
    }

    public static double random(Object a, Object b) {
        double x = Lc.toNum(a);
        double y = Lc.toNum(b);
        x = x < 0 ? Math.ceil(x) : Math.floor(x);
        y = y < 0 ? Math.ceil(y) : Math.floor(y);
        double lo = x <= y ? x : y;
        double hi = x <= y ? y : x;
        return pz(lo + Math.floor(ThreadLocalRandom.current().nextDouble() * (hi - lo + 1)));
    }

    // —— 文字 ——

    public static Object charAt(Object s, Object i) {
        String text = Lc.toText(s);
        int n = index(i);
        if (n < 0 || n >= text.codePointCount(0, text.length())) return null;
        int at = text.offsetByCodePoints(0, n);
        return text.substring(at, text.offsetByCodePoints(at, 1));
    }

    public static String substring(Object s, Object from, Object to) {
        String text = Lc.toText(s);
        int count = text.codePointCount(0, text.length());
        int a = clamp(index(from), 0, count);
        int b = clamp(index(to), 0, count);
        if (a >= b) return "";
        int start = text.offsetByCodePoints(0, a);
        return text.substring(start, text.offsetByCodePoints(start, b - a));
    }

    public static boolean contains(Object s, Object sub) {
        return Lc.toText(s).contains(Lc.toText(sub));
    }

    public static boolean startsWith(Object s, Object p) {
        return Lc.toText(s).startsWith(Lc.toText(p));
    }

    public static boolean endsWith(Object s, Object p) {
        return Lc.toText(s).endsWith(Lc.toText(p));
    }

    public static double indexOf(Object s, Object sub) {
        String text = Lc.toText(s);
        int at = text.indexOf(Lc.toText(sub));
        return at < 0 ? -1 : text.codePointCount(0, at);
    }

    public static String replace(Object s, Object from, Object to) {
        String f = Lc.toText(from);
        return f.isEmpty() ? Lc.toText(s) : Lc.toText(s).replace(f, Lc.toText(to));
    }

    public static Object split(Object s, Object sep) {
        String text = Lc.toText(s);
        String p = Lc.toText(sep);
        List<Object> out = new ArrayList<>();
        if (p.isEmpty()) {
            for (int i = 0; i < text.length(); ) {
                int next = text.offsetByCodePoints(i, 1);
                out.add(text.substring(i, next));
                i = next;
            }
            return out;
        }
        int from = 0;
        while (true) {
            int at = text.indexOf(p, from);
            if (at < 0) break;
            out.add(text.substring(from, at));
            from = at + p.length();
        }
        out.add(text.substring(from));
        return out;
    }

    public static String trim(Object s) {
        String text = Lc.toText(s);
        int from = 0;
        int to = text.length();
        while (from < to && Lc.isBlank(text.charAt(from))) from++;
        while (to > from && Lc.isBlank(text.charAt(to - 1))) to--;
        return text.substring(from, to);
    }

    public static String upper(Object s) {
        char[] cs = Lc.toText(s).toCharArray();
        for (int i = 0; i < cs.length; i++) {
            if (cs[i] >= 'a' && cs[i] <= 'z') cs[i] = (char) (cs[i] - 32);
        }
        return new String(cs);
    }

    public static String lower(Object s) {
        char[] cs = Lc.toText(s).toCharArray();
        for (int i = 0; i < cs.length; i++) {
            if (cs[i] >= 'A' && cs[i] <= 'Z') cs[i] = (char) (cs[i] + 32);
        }
        return new String(cs);
    }

    public static String repeatText(Object s, Object n) {
        return Lc.toText(s).repeat(clamp(index(n), 0, RANGE_LIMIT));
    }

    public static String template(Object s, Object d) {
        Map<String, Object> dict = Lc.asObj(d);
        Matcher m = HOLE.matcher(Lc.toText(s));
        StringBuilder out = new StringBuilder();
        while (m.find()) {
            boolean has = dict != null && dict.containsKey(m.group(1));
            m.appendReplacement(out, Matcher.quoteReplacement(has ? Lc.toText(dict.get(m.group(1))) : m.group()));
        }
        m.appendTail(out);
        return out.toString();
    }

    // —— 列表 ——

    public static Object listOf(Object... xs) {
        return new ArrayList<Object>(Arrays.asList(xs));
    }

    public static Object listGet(Object xs, Object i) {
        List<Object> list = list(xs);
        int n = index(i);
        return n >= 0 && n < list.size() ? list.get(n) : null;
    }

    public static void listSet(Object xs, Object i, Object v) {
        List<Object> list = mustList(xs);
        int n = index(i);
        if (n < 0 || n >= list.size()) throw new LcError(E_NO_ITEM);
        list.set(n, v);
    }

    public static void listPush(Object xs, Object v) {
        mustList(xs).add(v);
    }

    public static void listInsert(Object xs, Object i, Object v) {
        List<Object> list = mustList(xs);
        int n = index(i);
        if (n < 0 || n > list.size()) throw new LcError(E_NO_ITEM);
        list.add(n, v);
    }

    public static Object listRemove(Object xs, Object i) {
        List<Object> list = mustList(xs);
        int n = index(i);
        if (n < 0 || n >= list.size()) throw new LcError(E_NO_ITEM);
        return list.remove(n);
    }

    public static Object listPop(Object xs) {
        List<Object> list = list(xs);
        return list.isEmpty() ? null : list.remove(list.size() - 1);
    }

    public static double listIndexOf(Object xs, Object v) {
        List<Object> list = list(xs);
        for (int i = 0; i < list.size(); i++) {
            if (Lc.eq(list.get(i), v)) return i;
        }
        return -1;
    }

    public static boolean listContains(Object xs, Object v) {
        return listIndexOf(xs, v) >= 0;
    }

    public static Object listSlice(Object xs, Object from, Object to) {
        List<Object> list = list(xs);
        int a = clamp(index(from), 0, list.size());
        int b = clamp(index(to), 0, list.size());
        return a >= b ? new ArrayList<Object>() : new ArrayList<Object>(list.subList(a, b));
    }

    public static Object listConcat(Object a, Object b) {
        List<Object> out = new ArrayList<>(list(a));
        out.addAll(list(b));
        return out;
    }

    public static Object listReverse(Object xs) {
        List<Object> list = list(xs);
        List<Object> out = new ArrayList<>(list.size());
        for (int i = list.size() - 1; i >= 0; i--) out.add(list.get(i));
        return out;
    }

    /** 数字排在前面、按大小；其余的文字化后按码点。 */
    public static Object listSort(Object xs) {
        List<Object> out = new ArrayList<>(list(xs));
        out.sort((x, y) -> {
            boolean nx = x instanceof Double;
            boolean ny = y instanceof Double;
            if (nx && ny) return Double.compare((Double) x + 0.0, (Double) y + 0.0);
            if (nx != ny) return nx ? -1 : 1;
            return LcJson.compareKeys(Lc.toText(x), Lc.toText(y));
        });
        return out;
    }

    public static String listJoin(Object xs, Object sep) {
        StringBuilder b = new StringBuilder();
        String p = Lc.toText(sep);
        boolean first = true;
        for (Object v : list(xs)) {
            if (!first) b.append(p);
            first = false;
            b.append(Lc.toText(v));
        }
        return b.toString();
    }

    /** “从…数到…”要做几遍。 */
    public static int countSteps(Object from, Object to, Object step) {
        double a = Lc.toNum(from);
        double s = Lc.toNum(step);
        if (s == 0) return 0;
        double d = (Lc.toNum(to) - a) / s;
        if (!(d >= 0)) return 0;
        if (d >= COUNT_LIMIT) return COUNT_LIMIT;
        double n = Math.floor(d + 1e-9) + 1;
        return n > COUNT_LIMIT ? COUNT_LIMIT : (int) n;
    }

    public static Object range(Object from, Object to, Object step) {
        double a = Lc.toNum(from);
        double s = Lc.toNum(step);
        int n = Math.min(countSteps(a, to, s), RANGE_LIMIT);
        List<Object> out = new ArrayList<>(n);
        for (int k = 0; k < n; k++) out.add(a + k * s);
        return out;
    }

    // —— 字典 ——

    public static Object dictOf(Object... pairs) {
        Map<String, Object> out = new HashMap<>();
        for (int i = 0; i + 1 < pairs.length; i += 2) out.put(Lc.toText(pairs[i]), pairs[i + 1]);
        return out;
    }

    public static boolean dictHas(Object d, Object k) {
        Map<String, Object> dict = Lc.asObj(d);
        return dict != null && dict.containsKey(Lc.toText(k));
    }

    public static Object dictGet(Object d, Object k) {
        Map<String, Object> dict = Lc.asObj(d);
        return dict == null ? null : dict.get(Lc.toText(k));
    }

    public static void dictSet(Object d, Object k, Object v) {
        mustDict(d).put(Lc.toText(k), v);
    }

    public static void dictRemove(Object d, Object k) {
        mustDict(d).remove(Lc.toText(k));
    }

    public static Object dictKeys(Object d) {
        return new ArrayList<Object>(keys(d));
    }

    public static Object dictValues(Object d) {
        List<Object> out = new ArrayList<>();
        for (String k : keys(d)) out.add(Lc.asObj(d).get(k));
        return out;
    }

    public static Object dictPairs(Object d) {
        List<Object> out = new ArrayList<>();
        for (String k : keys(d)) {
            List<Object> pair = new ArrayList<>(2);
            pair.add(k);
            pair.add(Lc.asObj(d).get(k));
            out.add(pair);
        }
        return out;
    }

    public static Object dictMerge(Object a, Object b) {
        Map<String, Object> out = new HashMap<>();
        if (Lc.asObj(a) != null) out.putAll(Lc.asObj(a));
        if (Lc.asObj(b) != null) out.putAll(Lc.asObj(b));
        return out;
    }

    // —— 列表 / 字典 / 文字通用 ——

    public static Object item(Object x, Object k) {
        if (x instanceof List) return listGet(x, k);
        if (x instanceof Map) return dictGet(x, k);
        return x instanceof String ? charAt(x, k) : null;
    }

    public static void setItem(Object x, Object k, Object v) {
        if (x instanceof List) {
            listSet(x, k, v);
        } else if (x instanceof Map) {
            dictSet(x, k, v);
        } else {
            throw new LcError(E_NOT_INDEXABLE);
        }
    }

    // —— JSON ——

    public static String toJson(Object x) {
        return LcJson.write(x);
    }

    public static Object fromJson(Object s) {
        return LcJson.parse(Lc.toText(s).getBytes(StandardCharsets.UTF_8));
    }
}
''';
