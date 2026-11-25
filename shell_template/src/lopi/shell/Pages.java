package lopi.shell;

/** 壳自带的几页说明（出错时给用户看的大白话）。不联网、不引外部资源。 */
final class Pages {
    private Pages() {}

    private static String page(String title, String... paragraphs) {
        StringBuilder sb = new StringBuilder();
        sb.append("<!doctype html><html lang=\"zh-CN\"><head><meta charset=\"utf-8\">")
                .append("<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">")
                .append("<title>").append(Paths.escapeHtml(title)).append("</title><style>")
                .append("body{margin:0;padding:32px 24px;font:16px/1.7 sans-serif;color:#1f2937;background:#fff}")
                .append("h1{font-size:20px;margin:0 0 16px}p{margin:0 0 12px}code{word-break:break-all}")
                .append("@media(prefers-color-scheme:dark){body{color:#e5e7eb;background:#121212}}")
                .append("</style></head><body><h1>").append(Paths.escapeHtml(title)).append("</h1>");
        for (String p : paragraphs) {
            if (p != null && !p.isEmpty()) {
                sb.append("<p>").append(p).append("</p>");
            }
        }
        return sb.append("</body></html>").toString();
    }

    /** 安装包里没有入口网页（空模板，或打包时没放进去）。 */
    static String noEntry(ShellConfig config) {
        return page(
                "这个应用里没有找到网页",
                "应用启动后要打开的网页是 <code>assets/www/" + Paths.escapeHtml(config.entry)
                        + "</code>，但安装包里没有这个文件。",
                config.problem == null ? null : "另外：" + Paths.escapeHtml(config.problem),
                "这不是你手机的问题，是打包时出的问题。请回到 LopiCode，确认项目里有入口网页，再重新打包安装。");
    }

    static String notFound(String path) {
        return page(
                "找不到这个页面",
                "应用里没有 <code>" + Paths.escapeHtml(path) + "</code> 这个文件。",
                "按返回键可以回到上一页。");
    }
}
