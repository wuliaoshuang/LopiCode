import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.time.LocalDate;
import java.time.ZoneOffset;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Enumeration;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Stream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipFile;

/**
 * 写 assets/apk_shell/shell.json：模板的身份证，打包器和测试都靠它核对。
 * 用法：java tools/Describe.java <shell_template 目录> <shell.apk> <已有的 shell.json> <输出> <模板版本> <minSdk> <targetSdk> <build-tools 版本>
 * 模板内容没变（sha256 相同）时沿用已有文件里的构建日期，这样重复构建得到的文件一模一样。
 */
public final class Describe {
    public static void main(String[] a) throws Exception {
        Path src = new File(a[0]).toPath();
        File apk = new File(a[1]);
        byte[] apkBytes = Files.readAllBytes(apk.toPath());
        String sha = hex(MessageDigest.getInstance("SHA-256").digest(apkBytes));
        String manifest = new String(Files.readAllBytes(src.resolve("AndroidManifest.xml")), StandardCharsets.UTF_8);

        String date = LocalDate.now(ZoneOffset.UTC).toString();
        File old = new File(a[2]);
        if (old.isFile()) {
            String text = new String(Files.readAllBytes(old.toPath()), StandardCharsets.UTF_8);
            if (text.contains("\"sha256\": \"" + sha + "\"")) {
                Matcher m = Pattern.compile("\"buildDate\": \"([0-9-]+)\"").matcher(text);
                if (m.find()) {
                    date = m.group(1);
                }
            }
        }

        List<String> permissions = new ArrayList<String>();
        Matcher pm = Pattern.compile("<uses-permission\\s+android:name=\"([^\"]+)\"").matcher(manifest);
        while (pm.find()) {
            permissions.add(pm.group(1));
        }

        StringBuilder j = new StringBuilder("{\n");
        num(j, "templateVersion", a[4]);
        str(j, "file", "shell.apk");
        str(j, "sha256", sha);
        num(j, "sizeBytes", String.valueOf(apkBytes.length));
        str(j, "sourceSha256", sourceHash(src));
        str(j, "buildDate", date);
        num(j, "minSdk", a[5]);
        num(j, "targetSdk", a[6]);
        num(j, "compileSdk", a[6]);
        str(j, "buildTools", a[7]);
        j.append("  \"signed\": false,\n  \"zipAlignment\": 4,\n");
        str(j, "package", attr(manifest, "package"));
        num(j, "versionCode", attr(manifest, "android:versionCode"));
        str(j, "versionName", attr(manifest, "android:versionName"));
        str(j, "label", attr(manifest, "android:label"));
        str(j, "javaPackage", "lopi.shell");
        str(j, "mainActivity", attr(manifest.substring(manifest.indexOf("<activity")), "android:name"));
        j.append("  \"permissions\": ").append(list(permissions)).append(",\n");
        j.append("  \"supportedPermissions\": [\n")
                .append("    \"android.permission.INTERNET\",\n")
                .append("    \"android.permission.ACCESS_NETWORK_STATE\",\n")
                .append("    \"android.permission.CAMERA\",\n")
                .append("    \"android.permission.RECORD_AUDIO\",\n")
                .append("    \"android.permission.ACCESS_FINE_LOCATION\",\n")
                .append("    \"android.permission.ACCESS_COARSE_LOCATION\",\n")
                .append("    \"android.permission.VIBRATE\",\n")
                .append("    \"android.permission.WAKE_LOCK\"\n  ],\n");
        str(j, "localOrigin", "https://lopi.invalid");
        str(j, "wwwDir", "assets/www/");
        str(j, "configAsset", "assets/lopi_shell.json");
        j.append("  \"configDefaults\": {\n")
                .append("    \"entry\": \"index.html\",\n")
                .append("    \"spaFallback\": true,\n")
                .append("    \"externalLinks\": \"browser\",\n")
                .append("    \"background\": \"#FFFFFF\",\n")
                .append("    \"backgroundDark\": \"#121212\",\n")
                .append("    \"orientation\": \"auto\",\n")
                .append("    \"keepScreenOn\": false,\n")
                .append("    \"zoom\": false\n  },\n");
        j.append("  \"icons\": {\n")
                .append("    \"48\": \"res/mipmap-mdpi/ic_launcher.png\",\n")
                .append("    \"72\": \"res/mipmap-hdpi/ic_launcher.png\",\n")
                .append("    \"96\": \"res/mipmap-xhdpi/ic_launcher.png\",\n")
                .append("    \"144\": \"res/mipmap-xxhdpi/ic_launcher.png\",\n")
                .append("    \"192\": \"res/mipmap-xxxhdpi/ic_launcher.png\"\n  },\n");
        str(j, "iconStorage", "stored");
        str(j, "iconResourceId", "0x7f010000");
        str(j, "themeResourceId", "0x7f020000");
        j.append("  \"entries\": [\n");
        try (ZipFile zip = new ZipFile(apk)) {
            boolean first = true;
            for (Enumeration<? extends ZipEntry> e = zip.entries(); e.hasMoreElements(); ) {
                ZipEntry z = e.nextElement();
                if (!first) {
                    j.append(",\n");
                }
                first = false;
                j.append("    {\"name\": \"").append(z.getName()).append("\", \"method\": \"")
                        .append(z.getMethod() == ZipEntry.STORED ? "stored" : "deflated")
                        .append("\", \"size\": ").append(z.getSize())
                        .append(", \"compressedSize\": ").append(z.getCompressedSize())
                        .append(", \"crc32\": \"").append(String.format("%08x", z.getCrc())).append("\"}");
            }
        }
        j.append("\n  ]\n}\n");
        Files.write(new File(a[3]).toPath(), j.toString().getBytes(StandardCharsets.UTF_8));
    }

    /**
     * 源码目录的指纹：shell_template/ 下除 build/ 和 README.md 以外的所有文件，按相对路径排序，
     * 每个文件一行 “<文件的 sha256>  <相对路径>\n”，再对这段文字整体算 sha256。
     * test/apk_shell_template_test.dart 用同样的算法核对——源码改了没重编模板，测试就不过。
     */
    private static String sourceHash(Path root) throws Exception {
        List<String> names = new ArrayList<String>();
        try (Stream<Path> walk = Files.walk(root)) {
            walk.filter(Files::isRegularFile).forEach(p -> {
                String rel = root.relativize(p).toString().replace(File.separatorChar, '/');
                if (!rel.startsWith("build/") && !rel.equals("README.md")) {
                    names.add(rel);
                }
            });
        }
        Collections.sort(names);
        StringBuilder lines = new StringBuilder();
        for (String rel : names) {
            byte[] bytes = Files.readAllBytes(root.resolve(rel));
            lines.append(hex(MessageDigest.getInstance("SHA-256").digest(bytes))).append("  ").append(rel).append('\n');
        }
        return hex(MessageDigest.getInstance("SHA-256").digest(lines.toString().getBytes(StandardCharsets.UTF_8)));
    }

    private static String attr(String xml, String name) throws IOException {
        Matcher m = Pattern.compile("\\s" + Pattern.quote(name) + "=\"([^\"]*)\"").matcher(xml);
        if (!m.find()) {
            throw new IOException("清单里找不到 " + name);
        }
        return m.group(1);
    }

    private static String list(List<String> items) {
        StringBuilder sb = new StringBuilder("[");
        for (int i = 0; i < items.size(); i++) {
            sb.append(i > 0 ? ", " : "").append('"').append(items.get(i)).append('"');
        }
        return sb.append("]").toString();
    }

    private static void str(StringBuilder j, String key, String value) {
        j.append("  \"").append(key).append("\": \"").append(value).append("\",\n");
    }

    private static void num(StringBuilder j, String key, String value) {
        j.append("  \"").append(key).append("\": ").append(value).append(",\n");
    }

    private static String hex(byte[] bytes) {
        StringBuilder sb = new StringBuilder();
        for (byte b : bytes) {
            sb.append(String.format("%02x", b));
        }
        return sb.toString();
    }
}
