package lopi.shell;

import android.content.res.AssetManager;
import android.net.Uri;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;

import java.io.ByteArrayInputStream;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;

/**
 * 把固定的本地地址 https://lopi.invalid/ 映射到安装包里的 assets/www/。
 * 网页以为自己在一个普通的 https 网站上，所以相对路径、绝对路径、fetch、ES module 都照常能用。
 * 这个域名用的是 RFC 2606 保留的 .invalid 后缀，真实网络上永远解析不到，漏拦也不会连到别人的服务器。
 */
final class AssetServer {
    static final String HOST = "lopi.invalid";
    static final String ORIGIN = "https://" + HOST;
    private static final String WWW = "www/";

    private final AssetManager assets;
    private final ShellConfig config;

    AssetServer(AssetManager assets, ShellConfig config) {
        this.assets = assets;
        this.config = config;
    }

    /** 启动时打开的地址：入口文件的完整地址（这样入口放在子目录里时相对路径也对）。 */
    String entryUrl() {
        return new Uri.Builder().scheme("https").authority(HOST).path("/" + config.entry).build().toString();
    }

    static boolean isLocal(Uri uri) {
        return uri != null
                && "https".equalsIgnoreCase(uri.getScheme())
                && HOST.equalsIgnoreCase(uri.getHost())
                && uri.getPort() == -1;
    }

    /** 打开本地地址对应的文件（保存文件时用）；不是本地地址或文件不存在返回 null。 */
    InputStream openLocal(Uri uri) {
        if (!isLocal(uri)) {
            return null;
        }
        String rel = Paths.normalize(uri.getPath());
        if (rel == null) {
            return null;
        }
        return open(rel.isEmpty() ? config.entry : rel);
    }

    /** 不是本地地址返回 null（交给 WebView 自己去联网）。会在后台线程被调用。 */
    WebResourceResponse handle(WebResourceRequest request) {
        Uri uri = request.getUrl();
        if (!isLocal(uri)) {
            return null;
        }
        try {
            return serve(uri, request.getMethod(), request.getRequestHeaders(), request.isForMainFrame());
        } catch (Exception e) {
            return text(500, "Internal Error", "读取应用内文件时出错。");
        }
    }

    private WebResourceResponse serve(Uri uri, String method, Map<String, String> headers, boolean mainFrame)
            throws IOException {
        if (!"GET".equalsIgnoreCase(method) && !"HEAD".equalsIgnoreCase(method)) {
            return text(405, "Method Not Allowed", "应用内的文件只能读取，不能提交。");
        }
        String path = uri.getPath() == null ? "/" : uri.getPath();
        String accept = header(headers, "Accept");
        boolean wantsPage = mainFrame || (accept != null && accept.contains("text/html"));
        String rel = Paths.normalize(path);
        if (rel == null) {
            return wantsPage ? html(404, "Not Found", Pages.notFound(path)) : text(404, "Not Found", "Not Found");
        }
        if (rel.isEmpty()) {
            rel = config.entry;
        }
        InputStream in = open(rel);
        boolean entryMissing = in == null && rel.equals(config.entry);
        if (in == null && !entryMissing && wantsPage && config.spaFallback && !Paths.looksLikeFile(rel)) {
            // 单页应用的路由（/user/12 这类不带扩展名的地址）刷新时回到入口，由网页自己的路由接手。
            rel = config.entry;
            in = open(rel);
            entryMissing = in == null;
        }
        if (in == null) {
            if (!wantsPage) {
                return text(404, "Not Found", "Not Found");
            }
            return html(404, "Not Found", entryMissing ? Pages.noEntry(config) : Pages.notFound(path));
        }

        String mime = Paths.mime(rel);
        String encoding = Paths.isText(mime) ? "utf-8" : null;
        Map<String, String> out = baseHeaders();
        // 安装包里的文件，available() 给的就是整份文件还剩多少字节。
        long total = in.available();
        long[] range = Paths.parseRange(header(headers, "Range"), total);
        if (range != null) {
            skipFully(in, range[0]);
            out.put("Content-Range", "bytes " + range[0] + "-" + range[1] + "/" + total);
            return new WebResourceResponse(
                    mime, encoding, 206, "Partial Content", out, new Bounded(in, range[1] - range[0] + 1));
        }
        return new WebResourceResponse(mime, encoding, 200, "OK", out, in);
    }

    private InputStream open(String rel) {
        try {
            return assets.open(WWW + rel);
        } catch (IOException e) {
            return null; // 文件不存在，或者这是个目录
        }
    }

    private static Map<String, String> baseHeaders() {
        Map<String, String> h = new HashMap<String, String>();
        // 不让 WebView 把应用内文件记进缓存：覆盖安装新版本后必须立刻看到新网页。
        h.put("Cache-Control", "no-store");
        h.put("Accept-Ranges", "bytes");
        return h;
    }

    private static String header(Map<String, String> headers, String name) {
        if (headers == null) {
            return null;
        }
        for (Map.Entry<String, String> e : headers.entrySet()) {
            if (name.equalsIgnoreCase(e.getKey())) {
                return e.getValue();
            }
        }
        return null;
    }

    private static WebResourceResponse html(int status, String reason, String body) {
        return new WebResourceResponse(
                "text/html", "utf-8", status, reason, baseHeaders(),
                new ByteArrayInputStream(body.getBytes(StandardCharsets.UTF_8)));
    }

    private static WebResourceResponse text(int status, String reason, String body) {
        return new WebResourceResponse(
                "text/plain", "utf-8", status, reason, baseHeaders(),
                new ByteArrayInputStream(body.getBytes(StandardCharsets.UTF_8)));
    }

    private static void skipFully(InputStream in, long count) throws IOException {
        long left = count;
        while (left > 0) {
            long n = in.skip(left);
            if (n <= 0) {
                if (in.read() < 0) {
                    return;
                }
                n = 1;
            }
            left -= n;
        }
    }

    /** 只放行前 limit 个字节（Range 请求用）。 */
    private static final class Bounded extends FilterInputStream {
        private long left;

        Bounded(InputStream in, long limit) {
            super(in);
            left = limit;
        }

        @Override
        public int read() throws IOException {
            if (left <= 0) {
                return -1;
            }
            int b = in.read();
            if (b >= 0) {
                left--;
            }
            return b;
        }

        @Override
        public int read(byte[] buf, int off, int len) throws IOException {
            if (left <= 0) {
                return -1;
            }
            int n = in.read(buf, off, (int) Math.min(len, left));
            if (n > 0) {
                left -= n;
            }
            return n;
        }

        @Override
        public long skip(long n) throws IOException {
            long s = in.skip(Math.min(n, left));
            left -= s;
            return s;
        }

        @Override
        public int available() throws IOException {
            return (int) Math.min(in.available(), left);
        }
    }
}
