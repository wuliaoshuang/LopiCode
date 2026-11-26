package lopi.shell;

import java.util.Arrays;

/**
 * 开发机上能直接跑的自测（不进安装包）：只测不碰安卓类的那部分逻辑——路径换算、MIME、Range。
 * build.sh 每次都会跑；有一条不过就停止构建。
 */
public final class ShellSelfTest {
    private static int failed;
    private static int count;

    private static void eq(String what, Object actual, Object expected) {
        count++;
        boolean same = actual == null ? expected == null : actual.equals(expected);
        if (!same) {
            failed++;
            System.err.println("✗ " + what + "：得到 " + actual + "，应该是 " + expected);
        }
    }

    private static String range(String header, long total) {
        long[] r = Paths.parseRange(header, total);
        return r == null ? null : Arrays.toString(r);
    }

    public static void main(String[] args) {
        // 路径
        eq("根", Paths.normalize("/"), "");
        eq("空", Paths.normalize(""), "");
        eq("空指针", Paths.normalize(null), "");
        eq("普通文件", Paths.normalize("/js/app.js"), "js/app.js");
        eq("重复斜杠", Paths.normalize("//js///app.js"), "js/app.js");
        eq("当前目录", Paths.normalize("/./js/./app.js"), "js/app.js");
        eq("目录地址补 index.html", Paths.normalize("/docs/"), "docs/index.html");
        eq("越界 1", Paths.normalize("/../secret"), null);
        eq("越界 2", Paths.normalize("/a/../../b"), null);
        eq("越界 3（结尾）", Paths.normalize("/a/.."), null);
        eq("反斜杠", Paths.normalize("/a\\..\\b"), null);
        eq("控制字符", Paths.normalize("/a\u0000b"), null);
        eq("带点的文件名不算越界", Paths.normalize("/a/..b/c...d"), "a/..b/c...d");
        eq("中文和空格", Paths.normalize("/图片/我 的.png"), "图片/我 的.png");

        // 入口写法
        eq("入口默认", Paths.cleanEntry("index.html"), "index.html");
        eq("入口带 ./", Paths.cleanEntry("./app/index.html"), "app/index.html");
        eq("入口带 /", Paths.cleanEntry("/index.html"), "index.html");
        eq("入口越界", Paths.cleanEntry("../index.html"), null);
        eq("入口是目录", Paths.cleanEntry("app/"), null);
        eq("入口为空", Paths.cleanEntry("  "), null);
        eq("入口不是字符串", Paths.cleanEntry(Integer.valueOf(3)), null);
        eq("入口带参数", Paths.cleanEntry("index.html?a=1"), null);

        // 是不是文件
        eq("路由", Paths.looksLikeFile("user/12"), false);
        eq("文件", Paths.looksLikeFile("user/12.json"), true);
        eq("目录带点、末段不带", Paths.looksLikeFile("v1.2/user"), false);

        // MIME
        eq("html", Paths.mime("index.html"), "text/html");
        eq("js", Paths.mime("a/b.js"), "text/javascript");
        eq("mjs", Paths.mime("m.mjs"), "text/javascript");
        eq("大写扩展名", Paths.mime("A.PNG"), "image/png");
        eq("wasm", Paths.mime("x.wasm"), "application/wasm");
        eq("没扩展名", Paths.mime("LICENSE"), "application/octet-stream");
        eq("目录带点", Paths.mime("v1.2/LICENSE"), "application/octet-stream");
        eq("不认识的", Paths.mime("a.xyz"), "application/octet-stream");
        eq("json 算文字", Paths.isText("application/json"), true);
        eq("svg 算文字", Paths.isText("image/svg+xml"), true);
        eq("png 不算文字", Paths.isText("image/png"), false);

        // Range
        eq("没有", range(null, 100), null);
        eq("前 10 字节", range("bytes=0-9", 100), "[0, 9]");
        eq("到结尾", range("bytes=10-", 100), "[10, 99]");
        eq("最后 10 字节", range("bytes=-10", 100), "[90, 99]");
        eq("终点越界收回", range("bytes=50-500", 100), "[50, 99]");
        eq("后缀比文件大", range("bytes=-500", 100), "[0, 99]");
        eq("起点越界", range("bytes=100-", 100), null);
        eq("反了", range("bytes=9-0", 100), null);
        eq("多段", range("bytes=0-1,5-6", 100), null);
        eq("乱写", range("bytes=a-b", 100), null);
        eq("别的单位", range("items=0-1", 100), null);
        eq("空文件", range("bytes=0-", 0), null);

        // 转义
        eq("转义", Paths.escapeHtml("<a href=\"x\">&</a>"), "&lt;a href=&quot;x&quot;&gt;&amp;&lt;/a&gt;");

        if (failed > 0) {
            System.err.println("壳自测：" + count + " 条里有 " + failed + " 条不过");
            System.exit(1);
        }
        System.out.println("壳自测：" + count + " 条全过");
    }
}
