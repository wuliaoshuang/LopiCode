/// Java 语言核心小库里“函数”那一部分（积木第 4 版·第 2 阶段）：函数值、调用、拿函数当参数的 8 个列表操作。
/// 放进 `LcLang` 这个类的最后（见 [javaLangRuntime]）；`Lc.Fn`、`Lc.FnBody` 在 `Lc.java`（runtime_java.dart）里。
/// 规矩见 lib/lang/rt.dart；五种语言要一起改。
library;

/// 把函数那一部分接进 `LcLang` 类里（[lang] 的最后一个 `}` 之前）。
String javaLangRuntime(String lang) {
  final body = lang.trimRight();
  return '${body.substring(0, body.length - 1)}${kJavaLangFuncSource.trimRight()}\n}\n';
}

const String kJavaLangFuncSource = r'''
    // —— 函数（第 2 阶段）——

    static final String E_NOT_FUNCTION = "这不是函数，不能调用";
    static final String E_ARG_COUNT = "调用函数时给的参数个数对不上";

    /** 造一个函数值：名字、最少 / 最多收几个参数（最多是 -1＝不限）、实现（收一个参数表）。 */
    public static Lc.Fn fn(String name, int min, int max, Lc.FnBody body) {
        return new Lc.Fn(name, min, max, body);
    }

    static Lc.Fn needFn(Object f) {
        if (!(f instanceof Lc.Fn)) throw new LcError(E_NOT_FUNCTION);
        return (Lc.Fn) f;
    }

    /** 调一个函数值：不是函数、参数个数对不上 → 抛错。没有返回值的函数得空。 */
    public static Object call(Object f, Object... args) {
        Lc.Fn fn = needFn(f);
        Object[] a = args == null ? new Object[] {null} : args;
        if (a.length < fn.min || (fn.max >= 0 && a.length > fn.max)) throw new LcError(E_ARG_COUNT);
        return fn.body.call(a);
    }

    /** 取第 i 个参数；没给就是空。 */
    public static Object arg(Object[] args, int i) {
        return i < args.length ? args[i] : null;
    }

    /** 取第 i 个参数；没给就用默认值。 */
    public static Object argOr(Object[] args, int i, Object d) {
        return i < args.length ? args[i] : d;
    }

    /** 把第 i 个起剩下的参数收成一个列表。 */
    public static Object rest(Object[] args, int i) {
        List<Object> out = new ArrayList<>();
        for (int k = i; k < args.length; k++) out.add(args[k]);
        return out;
    }

    /** 开始时把列表抄一份再走：回调里改了原来的列表也不影响这一趟。 */
    static List<Object> each(Object xs, Object f) {
        needFn(f);
        return new ArrayList<>(list(xs));
    }

    public static Object listMap(Object xs, Object f) {
        List<Object> out = new ArrayList<>();
        for (Object x : each(xs, f)) out.add(call(f, x));
        return out;
    }

    public static Object listFilter(Object xs, Object f) {
        List<Object> out = new ArrayList<>();
        for (Object x : each(xs, f)) {
            if (Lc.truthy(call(f, x))) out.add(x);
        }
        return out;
    }

    public static Object listReduce(Object xs, Object f, Object init) {
        Object acc = init;
        for (Object x : each(xs, f)) acc = call(f, acc, x);
        return acc;
    }

    public static Object listFind(Object xs, Object f) {
        for (Object x : each(xs, f)) {
            if (Lc.truthy(call(f, x))) return x;
        }
        return null;
    }

    public static boolean listEvery(Object xs, Object f) {
        for (Object x : each(xs, f)) {
            if (!Lc.truthy(call(f, x))) return false;
        }
        return true;
    }

    public static boolean listSome(Object xs, Object f) {
        for (Object x : each(xs, f)) {
            if (Lc.truthy(call(f, x))) return true;
        }
        return false;
    }

    public static void listEach(Object xs, Object f) {
        for (Object x : each(xs, f)) call(f, x);
    }

    /** 按 f(项) 给的分从小到大：分是数字的排前面、按大小；其余的文字化后按码点；一样的保持原来的先后。 */
    public static Object listSortBy(Object xs, Object f) {
        List<Object> items = each(xs, f);
        List<Object[]> keyed = new ArrayList<>();
        for (Object x : items) keyed.add(new Object[] {call(f, x), x});
        keyed.sort((p, q) -> {
            Object x = p[0];
            Object y = q[0];
            boolean nx = x instanceof Double;
            boolean ny = y instanceof Double;
            if (nx && ny) return Double.compare((Double) x + 0.0, (Double) y + 0.0);
            if (nx != ny) return nx ? -1 : 1;
            return LcJson.compareKeys(Lc.toText(x), Lc.toText(y));
        });
        List<Object> out = new ArrayList<>();
        for (Object[] p : keyed) out.add(p[1]);
        return out;
    }
''';
