package lopi.shell;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/**
 * 不碰任何安卓类的纯逻辑：把网址路径换成 assets/www/ 下的相对路径、按扩展名给 MIME、解析 Range。
 * 单独放一个类是为了能在开发机上直接跑自测（selftest/ShellSelfTest.java）。
 */
final class Paths {
    private Paths() {}

    private static final Map<String, String> MIME = new HashMap<String, String>();

    static {
        String[] table = {
            "html", "text/html", "htm", "text/html", "xhtml", "application/xhtml+xml",
            "js", "text/javascript", "mjs", "text/javascript", "cjs", "text/javascript",
            "css", "text/css", "json", "application/json", "map", "application/json",
            "webmanifest", "application/manifest+json", "xml", "text/xml", "txt", "text/plain",
            "md", "text/markdown", "csv", "text/csv", "vtt", "text/vtt",
            "svg", "image/svg+xml", "png", "image/png", "jpg", "image/jpeg", "jpeg", "image/jpeg",
            "gif", "image/gif", "webp", "image/webp", "avif", "image/avif", "ico", "image/x-icon",
            "bmp", "image/bmp", "apng", "image/apng",
            "woff", "font/woff", "woff2", "font/woff2", "ttf", "font/ttf", "otf", "font/otf",
            "eot", "application/vnd.ms-fontobject",
            "wasm", "application/wasm", "pdf", "application/pdf", "zip", "application/zip",
            "mp3", "audio/mpeg", "m4a", "audio/mp4", "aac", "audio/aac", "wav", "audio/wav",
            "ogg", "audio/ogg", "oga", "audio/ogg", "opus", "audio/ogg", "flac", "audio/flac",
            "weba", "audio/webm",
            "mp4", "video/mp4", "m4v", "video/mp4", "webm", "video/webm", "ogv", "video/ogg",
            "mov", "video/quicktime",
            "glb", "model/gltf-binary", "gltf", "model/gltf+json",
        };
        for (int i = 0; i < table.length; i += 2) {
            MIME.put(table[i], table[i + 1]);
        }
    }

    /**
     * 把网址里的路径（已经解过百分号）换成相对 www/ 的路径。
     * 返回 ""＝根（调用方换成入口文件）；返回 null＝不合法（含 ..、反斜杠、控制字符），一律当找不到。
     * 以 / 结尾的目录地址补上 index.html。
     */
    static String normalize(String rawPath) {
        if (rawPath == null || rawPath.isEmpty()) {
            return "";
        }
        ArrayList<String> out = new ArrayList<String>();
        for (String seg : rawPath.split("/", -1)) {
            if (seg.isEmpty() || seg.equals(".")) {
                continue;
            }
            if (seg.equals("..")) {
                return null;
            }
            for (int i = 0; i < seg.length(); i++) {
                char c = seg.charAt(i);
                if (c < 0x20 || c == '\\' || c == 0x7f) {
                    return null;
                }
            }
            out.add(seg);
        }
        if (out.isEmpty()) {
            return "";
        }
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < out.size(); i++) {
            if (i > 0) {
                sb.append('/');
            }
            sb.append(out.get(i));
        }
        if (rawPath.endsWith("/")) {
            sb.append("/index.html");
        }
        return sb.toString();
    }

    /** 设置文件里的入口写法是否能用；能用返回整理后的相对路径，不能用返回 null。 */
    static String cleanEntry(Object raw) {
        if (!(raw instanceof String)) {
            return null;
        }
        String s = ((String) raw).trim();
        if (s.isEmpty() || s.endsWith("/") || s.indexOf('?') >= 0 || s.indexOf('#') >= 0) {
            return null;
        }
        String rel = normalize(s);
        return rel == null || rel.isEmpty() ? null : rel;
    }

    /** 最后一段带不带扩展名。不带的（/user/12）才算“页面路由”，可以回退到入口。 */
    static boolean looksLikeFile(String rel) {
        int slash = rel.lastIndexOf('/');
        return rel.indexOf('.', slash + 1) >= 0;
    }

    static String mime(String rel) {
        int slash = rel.lastIndexOf('/');
        int dot = rel.lastIndexOf('.');
        if (dot <= slash) {
            return "application/octet-stream";
        }
        String type = MIME.get(rel.substring(dot + 1).toLowerCase(Locale.ROOT));
        return type == null ? "application/octet-stream" : type;
    }

    /** 文字类的要带上 utf-8，不然中文会乱码。 */
    static boolean isText(String mime) {
        return mime.startsWith("text/") || mime.endsWith("json") || mime.endsWith("xml");
    }

    /**
     * 解析 Range 请求头。返回 {起点, 终点(含)}；写法不认识、多段、越界都返回 null（调用方整份返回）。
     */
    static long[] parseRange(String header, long total) {
        if (header == null || total <= 0) {
            return null;
        }
        String h = header.trim();
        if (!h.startsWith("bytes=") || h.indexOf(',') >= 0) {
            return null;
        }
        String spec = h.substring(6).trim();
        int dash = spec.indexOf('-');
        if (dash < 0) {
            return null;
        }
        String a = spec.substring(0, dash).trim();
        String b = spec.substring(dash + 1).trim();
        try {
            long start;
            long end;
            if (a.isEmpty()) {
                if (b.isEmpty()) {
                    return null;
                }
                long suffix = Long.parseLong(b);
                if (suffix <= 0) {
                    return null;
                }
                start = Math.max(0, total - suffix);
                end = total - 1;
            } else {
                start = Long.parseLong(a);
                end = b.isEmpty() ? total - 1 : Math.min(Long.parseLong(b), total - 1);
            }
            if (start < 0 || start >= total || end < start) {
                return null;
            }
            return new long[] {start, end};
        } catch (NumberFormatException e) {
            return null;
        }
    }

    static String escapeHtml(String s) {
        StringBuilder sb = new StringBuilder(s.length() + 16);
        for (int i = 0; i < s.length(); i++) {
            char c = s.charAt(i);
            switch (c) {
                case '<': sb.append("&lt;"); break;
                case '>': sb.append("&gt;"); break;
                case '&': sb.append("&amp;"); break;
                case '"': sb.append("&quot;"); break;
                default: sb.append(c);
            }
        }
        return sb.toString();
    }
}
