/// Java 运行时小库的源码（JSON 的读和写、数字的写法；生成的工程里的 `LcJson.java`）。每份工程都一样。
///
/// 只用 JDK 自带的东西。值的规矩见 backend_ir.dart 的 `kBeRuntimeFns`，改这里的行为要同时改别的语言的小库
/// （`test/backend_conformance_test.dart` 会让各语言跑同一套请求、比对响应是否逐字节相同）。
library;

const String kJavaRuntimeJsonSource = r'''
// LopiCode 后端运行时小库（Java）：JSON 的读和写、数字的写法。JDK 不带 JSON，所以自己写了一个小的。
import java.math.BigDecimal;
import java.math.MathContext;
import java.math.RoundingMode;
import java.nio.ByteBuffer;
import java.nio.charset.CharacterCodingException;
import java.nio.charset.CodingErrorAction;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

final class LcJson {
    private LcJson() {}

    private static final MathContext ROUND12 = new MathContext(12, RoundingMode.HALF_UP);

    /** 数字的写法：整数不带小数点；其余保留 12 位有效数字（0.1 + 0.2 写成 0.3）。 */
    static String fmtNum(double v) {
        if (Double.isNaN(v) || Double.isInfinite(v) || v == 0) return "0";
        if (v == Math.floor(v) && Math.abs(v) < 1e15) return Long.toString((long) v);
        BigDecimal d = new BigDecimal(v).round(ROUND12); // new BigDecimal(double) 是精确值，不会二次舍入
        String digits = d.unscaledValue().abs().toString();
        int e = digits.length() - 1 - d.scale();
        int end = digits.length();
        while (end > 1 && digits.charAt(end - 1) == '0') end--;
        digits = digits.substring(0, end);
        String minus = v < 0 ? "-" : "";
        if (e >= 15 || e < -7) return minus + digits.charAt(0) + (digits.length() > 1 ? "." + digits.substring(1) : "") + "e" + e;
        if (e >= digits.length() - 1) return minus + digits + "0".repeat(e - digits.length() + 1);
        if (e >= 0) return minus + digits.substring(0, e + 1) + "." + digits.substring(e + 1);
        return minus + "0." + "0".repeat(-e - 1) + digits;
    }

    /** 按 Unicode 码点比较两个键（Java 默认按 UTF-16 比，表情符号的顺序会和别的语言不一样）。 */
    static int compareKeys(String a, String b) {
        int i = 0;
        int j = 0;
        while (i < a.length() && j < b.length()) {
            int x = a.codePointAt(i);
            int y = b.codePointAt(j);
            if (x != y) return x < y ? -1 : 1;
            i += Character.charCount(x);
            j += Character.charCount(y);
        }
        return (a.length() - i) - (b.length() - j);
    }

    private static void quote(StringBuilder b, String s) {
        b.append('"');
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '"':
                    b.append("\\\"");
                    break;
                case '\\':
                    b.append("\\\\");
                    break;
                case '\n':
                    b.append("\\n");
                    break;
                case '\r':
                    b.append("\\r");
                    break;
                case '\t':
                    b.append("\\t");
                    break;
                case '\b':
                    b.append("\\b");
                    break;
                case '\f':
                    b.append("\\f");
                    break;
                default:
                    if (c < 0x20) {
                        b.append("\\u00").append(Character.forDigit(c >> 4, 16)).append(Character.forDigit(c & 15, 16));
                    } else {
                        b.append(c);
                    }
            }
        }
        b.append('"');
    }

    private static void write(StringBuilder b, Object v) {
        if (v == null) {
            b.append("null");
        } else if (v instanceof Boolean) {
            b.append((Boolean) v ? "true" : "false");
        } else if (v instanceof Double) {
            b.append(fmtNum((Double) v));
        } else if (v instanceof String) {
            quote(b, (String) v);
        } else if (v instanceof List) {
            b.append('[');
            boolean first = true;
            for (Object item : (List<?>) v) {
                if (!first) b.append(',');
                first = false;
                write(b, item);
            }
            b.append(']');
        } else if (v instanceof Map) {
            Map<?, ?> map = (Map<?, ?>) v;
            List<String> keys = new ArrayList<>();
            for (Object k : map.keySet()) keys.add((String) k);
            keys.sort(LcJson::compareKeys);
            b.append('{');
            boolean first = true;
            for (String k : keys) {
                if (!first) b.append(',');
                first = false;
                quote(b, k);
                b.append(':');
                write(b, map.get(k));
            }
            b.append('}');
        } else {
            b.append("null");
        }
    }

    /** 写成 JSON：对象的键排好序，数字按上面的写法。 */
    static String write(Object v) {
        StringBuilder b = new StringBuilder();
        write(b, v);
        return b.toString();
    }

    /** 把请求内容按 JSON 解出来；没有内容、不是合法 UTF-8、不是合法 JSON、套得太深 → null。 */
    static Object parse(byte[] raw) {
        if (raw == null || raw.length == 0) return null;
        try {
            String text = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(raw)).toString();
            Parser p = new Parser(text);
            p.blank();
            Object v = p.value(0);
            p.blank();
            return p.at == text.length() ? v : null;
        } catch (CharacterCodingException | IllegalArgumentException e) {
            return null;
        }
    }

    /** 不成对的代理项（半个表情符号）换成 U+FFFD。 */
    static String wellFormed(String s) {
        StringBuilder b = null;
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            if (Character.isHighSurrogate(c) && i + 1 < s.length() && Character.isLowSurrogate(s.charAt(i + 1))) {
                i++;
            } else if (Character.isSurrogate(c)) {
                if (b == null) b = new StringBuilder(s);
                b.setCharAt(i, '\uFFFD');
            }
        }
        return b == null ? s : b.toString();
    }

    private static final class Parser {
        final String s;
        int at = 0;

        Parser(String s) {
            this.s = s;
        }

        IllegalArgumentException bad() {
            return new IllegalArgumentException("不是合法的 JSON");
        }

        char peek() {
            if (at >= s.length()) throw bad();
            return s.charAt(at);
        }

        void blank() {
            while (at < s.length() && Lc.isBlank(s.charAt(at))) at++;
        }

        void word(String w) {
            if (!s.startsWith(w, at)) throw bad();
            at += w.length();
        }

        Object value(int depth) {
            char c = peek();
            switch (c) {
                case '{':
                    return object(depth + 1);
                case '[':
                    return list(depth + 1);
                case '"':
                    return string();
                case 't':
                    word("true");
                    return Boolean.TRUE;
                case 'f':
                    word("false");
                    return Boolean.FALSE;
                case 'n':
                    word("null");
                    return null;
                default:
                    return number();
            }
        }

        Object object(int depth) {
            if (depth > Lc.JSON_DEPTH_LIMIT) throw bad();
            Map<String, Object> out = new HashMap<>();
            at++;
            blank();
            if (peek() == '}') {
                at++;
                return out;
            }
            while (true) {
                blank();
                if (peek() != '"') throw bad();
                String key = string();
                blank();
                if (peek() != ':') throw bad();
                at++;
                blank();
                out.put(key, value(depth)); // 键重复时后面的盖掉前面的
                blank();
                char c = peek();
                at++;
                if (c == '}') return out;
                if (c != ',') throw bad();
            }
        }

        Object list(int depth) {
            if (depth > Lc.JSON_DEPTH_LIMIT) throw bad();
            List<Object> out = new ArrayList<>();
            at++;
            blank();
            if (peek() == ']') {
                at++;
                return out;
            }
            while (true) {
                blank();
                out.add(value(depth));
                blank();
                char c = peek();
                at++;
                if (c == ']') return out;
                if (c != ',') throw bad();
            }
        }

        String string() {
            StringBuilder b = new StringBuilder();
            at++;
            while (true) {
                char c = peek();
                at++;
                if (c == '"') return wellFormed(b.toString());
                if (c < 0x20) throw bad();
                if (c != '\\') {
                    b.append(c);
                    continue;
                }
                char e = peek();
                at++;
                switch (e) {
                    case '"':
                    case '\\':
                    case '/':
                        b.append(e);
                        break;
                    case 'b':
                        b.append('\b');
                        break;
                    case 'f':
                        b.append('\f');
                        break;
                    case 'n':
                        b.append('\n');
                        break;
                    case 'r':
                        b.append('\r');
                        break;
                    case 't':
                        b.append('\t');
                        break;
                    case 'u':
                        if (at + 4 > s.length()) throw bad();
                        int code = 0;
                        for (int i = 0; i < 4; i++) {
                            int digit = Character.digit(s.charAt(at + i), 16);
                            // Character.digit 也认全角数字，这里只许 0-9 a-f A-F
                            if (digit < 0 || s.charAt(at + i) > 'f') throw bad();
                            code = code * 16 + digit;
                        }
                        at += 4;
                        b.append((char) code);
                        break;
                    default:
                        throw bad();
                }
            }
        }

        int digits() {
            int from = at;
            while (at < s.length() && Lc.isDigit(s.charAt(at))) at++;
            return at - from;
        }

        Object number() {
            int from = at;
            if (peek() == '-') at++;
            if (peek() == '0') {
                at++;
            } else if (digits() == 0) {
                throw bad();
            }
            if (at < s.length() && s.charAt(at) == '.') {
                at++;
                if (digits() == 0) throw bad();
            }
            if (at < s.length() && (s.charAt(at) == 'e' || s.charAt(at) == 'E')) {
                at++;
                if (at < s.length() && (s.charAt(at) == '+' || s.charAt(at) == '-')) at++;
                if (digits() == 0) throw bad();
            }
            // 超出范围的数（1e400）是无穷大，当 0
            return Lc.fin(Double.parseDouble(s.substring(from, at)));
        }
    }
}
''';
