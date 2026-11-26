package lopi.shell;

import android.content.pm.ActivityInfo;
import android.content.res.AssetManager;
import android.graphics.Color;

import org.json.JSONObject;

import java.io.ByteArrayOutputStream;
import java.io.FileNotFoundException;
import java.io.InputStream;

/**
 * 壳的设置，读自 assets/lopi_shell.json。每一项都有默认值：文件没有、坏了、某一项写错了，壳都照样能起来。
 * 各项的含义见 README.md 的「lopi_shell.json」。
 */
final class ShellConfig {
    static final String ASSET = "lopi_shell.json";
    private static final int MAX_BYTES = 64 * 1024;

    String entry = "index.html";
    boolean spaFallback = true;
    boolean externalInApp = false;
    int background = 0xFFFFFFFF;
    int backgroundDark = 0xFF121212;
    int orientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;
    boolean keepScreenOn = false;
    boolean zoom = false;

    /** 设置文件有问题时的大白话说明（只在找不到入口网页时显示）；没问题是 null。 */
    String problem;

    static ShellConfig load(AssetManager assets) {
        ShellConfig c = new ShellConfig();
        String text;
        try {
            InputStream in = assets.open(ASSET);
            try {
                ByteArrayOutputStream out = new ByteArrayOutputStream();
                byte[] buf = new byte[4096];
                int n;
                while ((n = in.read(buf)) > 0 && out.size() <= MAX_BYTES) {
                    out.write(buf, 0, n);
                }
                text = out.toString("UTF-8");
            } finally {
                in.close();
            }
        } catch (FileNotFoundException e) {
            return c; // 没有设置文件：全用默认值，这是正常情况。
        } catch (Exception e) {
            c.problem = "设置文件 assets/" + ASSET + " 读不出来，已全部按默认设置处理。";
            return c;
        }
        try {
            if (text.startsWith("\uFEFF")) {
                text = text.substring(1);
            }
            c.apply(new JSONObject(text));
        } catch (Exception e) {
            c.problem = "设置文件 assets/" + ASSET + " 不是合法的 JSON，已全部按默认设置处理。";
        }
        return c;
    }

    private void apply(JSONObject o) {
        if (o.has("entry")) {
            String e = Paths.cleanEntry(o.opt("entry"));
            if (e != null) {
                entry = e;
            } else {
                problem = "设置文件里的入口（entry）写法不对，已改用默认的 index.html。";
            }
        }
        spaFallback = bool(o, "spaFallback", spaFallback);
        keepScreenOn = bool(o, "keepScreenOn", keepScreenOn);
        zoom = bool(o, "zoom", zoom);
        externalInApp = "inapp".equals(o.opt("externalLinks"));
        background = color(o, "background", background);
        backgroundDark = color(o, "backgroundDark", backgroundDark);
        Object ori = o.opt("orientation");
        if ("portrait".equals(ori)) {
            orientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT;
        } else if ("landscape".equals(ori)) {
            orientation = ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE;
        }
    }

    private static boolean bool(JSONObject o, String key, boolean fallback) {
        Object v = o.opt(key);
        return v instanceof Boolean ? ((Boolean) v).booleanValue() : fallback;
    }

    private static int color(JSONObject o, String key, int fallback) {
        Object v = o.opt(key);
        if (v instanceof String) {
            String s = ((String) v).trim();
            if (s.length() == 7 && s.charAt(0) == '#') {
                try {
                    return Color.parseColor(s) | 0xFF000000;
                } catch (IllegalArgumentException e) {
                    return fallback; // 颜色写错了就用默认色
                }
            }
        }
        return fallback;
    }
}
