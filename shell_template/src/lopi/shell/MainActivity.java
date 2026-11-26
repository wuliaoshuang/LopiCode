package lopi.shell;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.ClipData;
import android.content.Intent;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Insets;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.view.WindowInsets;
import android.view.WindowInsetsController;
import android.view.WindowManager;
import android.webkit.CookieManager;
import android.webkit.MimeTypeMap;
import android.webkit.ServiceWorkerClient;
import android.webkit.ServiceWorkerController;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.widget.FrameLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.ArrayList;

/**
 * LopiCode 网页壳：打开安装包里 assets/www/ 的网页，离线可用。
 * 不带任何统计、联网上报、远程代码加载。行为说明见 shell_template/README.md。
 */
public final class MainActivity extends Activity {
    static final int REQ_WEB_PERMISSION = 1;
    static final int REQ_GEO_PERMISSION = 2;
    static final int REQ_PICK_FILE = 10;
    static final int REQ_SAVE_FILE = 11;

    ShellConfig config;
    AssetServer server;
    Permissions permissions;
    WebView web;

    private Downloads downloads;
    private FrameLayout root;
    private View customView;
    private WebChromeClient.CustomViewCallback customCallback;
    private ValueCallback<Uri[]> pendingFiles;

    @Override
    protected void onCreate(Bundle saved) {
        super.onCreate(saved);
        config = ShellConfig.load(getAssets());
        server = new AssetServer(getAssets(), config);
        permissions = new Permissions(this);
        downloads = new Downloads(this);

        if (config.orientation != android.content.pm.ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED) {
            setRequestedOrientation(config.orientation);
        }
        if (config.keepScreenOn) {
            getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        }

        root = new FrameLayout(this);
        setContentView(root);
        // 安卓 15 起（targetSdk 35）强制“边到边”：内容会画到状态栏和导航栏下面。
        // 这里把系统栏、刘海、键盘占的地方都留成内边距，网页永远不会被它们盖住。
        root.setOnApplyWindowInsetsListener(new View.OnApplyWindowInsetsListener() {
            @Override
            public WindowInsets onApplyWindowInsets(View v, WindowInsets insets) {
                if (Build.VERSION.SDK_INT >= 30) {
                    Insets i = insets.getInsets(WindowInsets.Type.systemBars()
                            | WindowInsets.Type.displayCutout()
                            | WindowInsets.Type.ime());
                    v.setPadding(i.left, i.top, i.right, i.bottom);
                    return WindowInsets.CONSUMED;
                }
                v.setPadding(insets.getSystemWindowInsetLeft(), insets.getSystemWindowInsetTop(),
                        insets.getSystemWindowInsetRight(), insets.getSystemWindowInsetBottom());
                return insets.consumeSystemWindowInsets();
            }
        });

        try {
            createWebView();
        } catch (Throwable t) {
            // 系统的网页组件被停用、正在更新或损坏时，new WebView 会直接抛错。
            web = null;
            showNoWebView();
            applyColors();
            return;
        }
        applyColors();
        if (saved == null || web.restoreState(saved) == null) {
            web.loadUrl(server.entryUrl());
        }
    }

    private void createWebView() {
        WebView w = new WebView(this);
        WebSettings s = w.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);
        s.setDatabaseEnabled(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setGeolocationEnabled(true);
        s.setSupportMultipleWindows(false);
        s.setUseWideViewPort(true);
        s.setLoadWithOverviewMode(true);
        s.setSupportZoom(config.zoom);
        s.setBuiltInZoomControls(config.zoom);
        s.setDisplayZoomControls(false);
        // 本地地址是 https，网页去连局域网里的 http 接口算“混合内容”，默认会被拦；这里放行。
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_ALWAYS_ALLOW);

        w.setWebViewClient(new ShellWebClient(this));
        w.setWebChromeClient(new ShellChromeClient(this));
        w.setDownloadListener(downloads);
        w.addJavascriptInterface(downloads.bridge(), Downloads.BRIDGE_NAME);
        // Service Worker 发的请求不经过上面的 WebViewClient，要单独接。
        ServiceWorkerController.getInstance().setServiceWorkerClient(new ServiceWorkerClient() {
            @Override
            public WebResourceResponse shouldInterceptRequest(WebResourceRequest request) {
                return server.handle(request);
            }
        });
        root.addView(w, 0, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        w.requestFocus();
        web = w;
    }

    /** 网页进程没了以后换一个新的（见 ShellWebClient.onRenderProcessGone）。 */
    void rebuildWebView() {
        exitFullscreen();
        if (web != null) {
            root.removeView(web);
            web.destroy();
            web = null;
        }
        try {
            createWebView();
            applyColors();
            web.loadUrl(server.entryUrl());
        } catch (Throwable t) {
            web = null;
            showNoWebView();
        }
    }

    private void showNoWebView() {
        TextView text = new TextView(this);
        int pad = (int) (24 * getResources().getDisplayMetrics().density);
        text.setPadding(pad, pad, pad, pad);
        text.setTextSize(16);
        text.setLineSpacing(0, 1.4f);
        text.setText("这个应用现在打不开\n\n"
                + "它要靠手机系统自带的“Android System WebView”（系统网页组件）来显示内容，"
                + "但这个组件现在用不了：可能正在更新、被停用了，或者版本太旧。\n\n"
                + "可以这样试：\n"
                + "1. 等一两分钟再打开（组件更新完就好了）。\n"
                + "2. 到应用商店把“Android System WebView”和“Chrome”更新到最新。\n"
                + "3. 到 设置 › 应用，确认“Android System WebView”没有被停用。\n\n"
                + "这不是这个应用本身坏了。");
        ScrollView scroll = new ScrollView(this);
        scroll.addView(text);
        root.addView(scroll, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
    }

    private boolean isNight() {
        return (getResources().getConfiguration().uiMode & Configuration.UI_MODE_NIGHT_MASK)
                == Configuration.UI_MODE_NIGHT_YES;
    }

    /** 背景色、状态栏和导航栏的颜色与图标深浅。深浅色切换、进出全屏时重新调一遍。 */
    @SuppressWarnings("deprecation")
    private void applyColors() {
        int bg = isNight() ? config.backgroundDark : config.background;
        if (customView != null) {
            bg = Color.BLACK;
        } else if (web != null) {
            web.setBackgroundColor(bg);
        }
        root.setBackgroundColor(bg);
        boolean lightBg = Color.luminance(bg) > 0.5f;
        Window window = getWindow();
        if (Build.VERSION.SDK_INT < 35) {
            // 安卓 15 起系统栏本身是透明的，露出来的就是上面的背景色；更早的版本要自己给系统栏上色。
            window.setStatusBarColor(bg);
            if (Build.VERSION.SDK_INT >= 26) {
                window.setNavigationBarColor(bg); // 26 以前导航栏图标只能是白的，保持系统默认的黑底
            }
        }
        if (Build.VERSION.SDK_INT >= 29) {
            window.setNavigationBarContrastEnforced(false);
            window.setStatusBarContrastEnforced(false);
        }
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = window.getInsetsController();
            if (c != null) {
                int mask = WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS
                        | WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS;
                c.setSystemBarsAppearance(lightBg ? mask : 0, mask);
            }
        } else {
            View decor = window.getDecorView();
            int flags = decor.getSystemUiVisibility();
            int mask = View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
                    | (Build.VERSION.SDK_INT >= 26 ? View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR : 0);
            decor.setSystemUiVisibility(lightBg ? (flags | mask) : (flags & ~mask));
        }
    }

    // ── 外链、提示 ──

    void openExternal(Uri uri) {
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW, uri);
            intent.addCategory(Intent.CATEGORY_BROWSABLE);
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
        } catch (ActivityNotFoundException e) {
            toast("手机上没有能打开这个链接的应用");
        } catch (SecurityException e) {
            toast("系统不允许打开这个链接");
        }
    }

    void toast(String message) {
        Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
    }

    // ── 选文件：系统文件选择器，不需要任何权限，也不需要 FileProvider ──

    boolean pickFiles(ValueCallback<Uri[]> callback, WebChromeClient.FileChooserParams params) {
        if (pendingFiles != null) {
            pendingFiles.onReceiveValue(null);
        }
        pendingFiles = callback;
        Intent intent = new Intent(Intent.ACTION_GET_CONTENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        ArrayList<String> types = new ArrayList<String>();
        String[] accept = params.getAcceptTypes();
        if (accept != null) {
            for (String raw : accept) {
                String t = raw == null ? "" : raw.trim();
                if (t.startsWith(".")) {
                    t = MimeTypeMap.getSingleton().getMimeTypeFromExtension(t.substring(1).toLowerCase());
                }
                if (t != null && t.indexOf('/') > 0 && !types.contains(t)) {
                    types.add(t);
                }
            }
        }
        if (types.size() == 1) {
            intent.setType(types.get(0));
        } else {
            intent.setType("*/*");
            if (types.size() > 1) {
                intent.putExtra(Intent.EXTRA_MIME_TYPES, types.toArray(new String[0]));
            }
        }
        if (params.getMode() == WebChromeClient.FileChooserParams.MODE_OPEN_MULTIPLE) {
            intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
        }
        try {
            startActivityForResult(intent, REQ_PICK_FILE);
        } catch (ActivityNotFoundException e) {
            pendingFiles = null;
            callback.onReceiveValue(null);
            toast("这台手机没有可用的“文件”应用，选不了文件");
        }
        return true;
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQ_PICK_FILE) {
            ValueCallback<Uri[]> callback = pendingFiles;
            pendingFiles = null;
            if (callback == null) {
                return;
            }
            Uri[] picked = null;
            if (resultCode == RESULT_OK && data != null) {
                ClipData clip = data.getClipData();
                if (clip != null && clip.getItemCount() > 0) {
                    picked = new Uri[clip.getItemCount()];
                    for (int i = 0; i < picked.length; i++) {
                        picked[i] = clip.getItemAt(i).getUri();
                    }
                } else if (data.getData() != null) {
                    picked = new Uri[] {data.getData()};
                }
            }
            callback.onReceiveValue(picked); // 取消也必须回一声（null），不然网页里的选文件按钮会卡死
        } else if (requestCode == REQ_SAVE_FILE) {
            downloads.onSaveResult(resultCode, data);
        }
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] names, int[] results) {
        super.onRequestPermissionsResult(requestCode, names, results);
        permissions.onResult(requestCode);
    }

    // ── 全屏视频 ──

    @SuppressWarnings("deprecation")
    void enterFullscreen(View view, WebChromeClient.CustomViewCallback callback) {
        if (customView != null) {
            callback.onCustomViewHidden();
            return;
        }
        customView = view;
        customCallback = callback;
        root.addView(view, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        if (web != null) {
            web.setVisibility(View.GONE);
        }
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = getWindow().getInsetsController();
            if (c != null) {
                c.setSystemBarsBehavior(WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE);
                c.hide(WindowInsets.Type.systemBars());
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(getWindow().getDecorView().getSystemUiVisibility()
                    | View.SYSTEM_UI_FLAG_FULLSCREEN
                    | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                    | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
        }
        applyColors();
    }

    @SuppressWarnings("deprecation")
    void exitFullscreen() {
        if (customView == null) {
            return;
        }
        root.removeView(customView);
        customView = null;
        if (customCallback != null) {
            customCallback.onCustomViewHidden();
            customCallback = null;
        }
        if (web != null) {
            web.setVisibility(View.VISIBLE);
        }
        if (Build.VERSION.SDK_INT >= 30) {
            WindowInsetsController c = getWindow().getInsetsController();
            if (c != null) {
                c.show(WindowInsets.Type.systemBars());
            }
        } else {
            getWindow().getDecorView().setSystemUiVisibility(getWindow().getDecorView().getSystemUiVisibility()
                    & ~(View.SYSTEM_UI_FLAG_FULLSCREEN
                            | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY));
        }
        applyColors();
    }

    // ── 返回键、生命周期 ──

    @Override
    @SuppressWarnings("deprecation")
    public void onBackPressed() {
        if (customView != null) {
            exitFullscreen();
        } else if (web != null && web.canGoBack()) {
            web.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    public void onConfigurationChanged(Configuration newConfig) {
        // 横竖屏、深浅色、字号等变化都不重建页面（清单里声明了自己处理），网页不会被重新加载。
        super.onConfigurationChanged(newConfig);
        applyColors();
    }

    @Override
    protected void onSaveInstanceState(Bundle out) {
        super.onSaveInstanceState(out);
        if (web != null) {
            web.saveState(out);
        }
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (web != null) {
            web.onResume();
        }
    }

    @Override
    protected void onPause() {
        if (web != null) {
            web.onPause();
            CookieManager.getInstance().flush();
        }
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        if (pendingFiles != null) {
            pendingFiles.onReceiveValue(null);
            pendingFiles = null;
        }
        if (web != null) {
            root.removeView(web);
            web.destroy();
            web = null;
        }
        super.onDestroy();
    }
}
