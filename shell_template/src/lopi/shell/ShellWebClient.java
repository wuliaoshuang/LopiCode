package lopi.shell;

import android.net.Uri;
import android.os.Build;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import java.util.Locale;

/** 拦截请求（本地地址 → 安装包里的文件）并决定每个链接在哪打开。 */
final class ShellWebClient extends WebViewClient {
    private final MainActivity activity;

    ShellWebClient(MainActivity activity) {
        this.activity = activity;
    }

    @Override
    public WebResourceResponse shouldInterceptRequest(WebView view, WebResourceRequest request) {
        return activity.server.handle(request);
    }

    @Override
    public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
        Uri uri = request.getUrl();
        if (AssetServer.isLocal(uri)) {
            return false;
        }
        String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(Locale.ROOT);
        if (scheme.equals("http") || scheme.equals("https")) {
            // 网页里嵌的外部内容（iframe）照常显示；整页跳到外部网站时默认交给系统浏览器。
            if (!request.isForMainFrame() || activity.config.externalInApp) {
                return false;
            }
            activity.openExternal(uri);
            return true;
        }
        if (scheme.equals("about") || scheme.equals("data") || scheme.equals("blob") || scheme.equals("javascript")) {
            return false;
        }
        if (scheme.equals("file") || scheme.equals("content")) {
            return true; // 不让网页直接翻手机里的文件
        }
        if (scheme.equals("intent") || scheme.equals("android-app")) {
            activity.toast("这个应用不支持打开这类链接");
            return true;
        }
        // tel:、mailto:、sms:、geo:、market: 以及其他应用自己的链接：交给系统找对应的应用。
        activity.openExternal(uri);
        return true;
    }

    @Override
    public boolean onRenderProcessGone(WebView view, RenderProcessGoneDetail detail) {
        // 网页进程被系统回收或崩了：不处理的话整个应用会跟着崩。这里换一个新的网页视图重新打开入口。
        if (Build.VERSION.SDK_INT >= 26) {
            activity.rebuildWebView();
            return true;
        }
        return false;
    }
}
