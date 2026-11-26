package lopi.shell;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.net.Uri;
import android.util.Base64;
import android.webkit.DownloadListener;
import android.webkit.JavascriptInterface;
import android.webkit.MimeTypeMap;
import android.webkit.URLUtil;

import org.json.JSONObject;

import java.io.ByteArrayInputStream;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;

/**
 * 网页触发“下载”时怎么办（WebView 自己不会下载）：
 * - 外部网址（http / https）：交给系统浏览器去下。
 * - 应用内的文件、data: 地址、blob: 地址（网页自己生成的导出文件）：弹系统的“保存到…”让用户选位置，
 *   壳把内容写进去。用的是系统文件选择器，不需要任何存储权限。
 */
final class Downloads implements DownloadListener {
    static final String BRIDGE_NAME = "LopiShellHost";

    private final MainActivity activity;

    /** 等用户选好保存位置后要写进去的内容：二选一。 */
    private byte[] pendingBytes;
    private Uri pendingLocal;

    /** 读 blob 用的一次性口令：只有壳刚注入的那段脚本知道，别的网页猜不到。 */
    private String blobToken;
    private String blobName;

    Downloads(MainActivity activity) {
        this.activity = activity;
    }

    Object bridge() {
        return new Bridge(this);
    }

    /** 暴露给网页脚本的唯一入口。只收“读 blob 的结果”，而且要带对一次性口令才理。 */
    public static final class Bridge {
        private final Downloads owner;

        Bridge(Downloads owner) {
            this.owner = owner;
        }

        @JavascriptInterface
        public void blob(final String token, final String dataUrl) {
            owner.activity.runOnUiThread(new Runnable() {
                @Override
                public void run() {
                    owner.onBlob(token, dataUrl);
                }
            });
        }
    }

    @Override
    public void onDownloadStart(String url, String userAgent, String contentDisposition, String mimeType, long length) {
        try {
            start(url, contentDisposition, mimeType);
        } catch (Exception e) {
            activity.toast("这个文件保存不了");
        }
    }

    private void start(String url, String contentDisposition, String mimeType) {
        Uri uri = Uri.parse(url);
        String scheme = uri.getScheme() == null ? "" : uri.getScheme();
        if (AssetServer.isLocal(uri)) {
            pendingLocal = uri;
            pendingBytes = null;
            askWhere(URLUtil.guessFileName(url, contentDisposition, mimeType), mimeType);
        } else if (scheme.equals("http") || scheme.equals("https")) {
            activity.openExternal(uri);
        } else if (scheme.equals("data")) {
            saveDataUrl(url, null);
        } else if (scheme.equals("blob") && activity.web != null) {
            byte[] raw = new byte[16];
            new SecureRandom().nextBytes(raw);
            StringBuilder token = new StringBuilder();
            for (byte b : raw) {
                token.append(String.format("%02x", b));
            }
            blobToken = token.toString();
            blobName = "download" + extensionFor(mimeType);
            String js = "(function(){var x=new XMLHttpRequest();x.open('GET'," + JSONObject.quote(url) + ",true);"
                    + "x.responseType='blob';x.onload=function(){var r=new FileReader();"
                    + "r.onloadend=function(){" + BRIDGE_NAME + ".blob('" + blobToken + "',String(r.result||''))};"
                    + "r.readAsDataURL(x.response)};"
                    + "x.onerror=function(){" + BRIDGE_NAME + ".blob('" + blobToken + "','')};x.send()})()";
            activity.web.evaluateJavascript(js, null);
        } else {
            activity.toast("这个应用保存不了这类文件");
        }
    }

    private void onBlob(String token, String dataUrl) {
        if (blobToken == null || !blobToken.equals(token)) {
            return; // 口令不对：不是壳自己发起的，不理
        }
        blobToken = null;
        if (dataUrl == null || !dataUrl.startsWith("data:")) {
            activity.toast("文件内容读不出来，没有保存");
            return;
        }
        try {
            saveDataUrl(dataUrl, blobName);
        } catch (Exception e) {
            activity.toast("文件内容读不出来，没有保存");
        }
    }

    private void saveDataUrl(String url, String name) {
        int comma = url.indexOf(',');
        if (comma < 0) {
            activity.toast("文件内容读不出来，没有保存");
            return;
        }
        String meta = url.substring(5, comma);
        String payload = url.substring(comma + 1);
        String mime = meta.split(";", -1)[0].trim();
        if (mime.isEmpty()) {
            mime = "text/plain";
        }
        pendingBytes = meta.contains(";base64")
                ? Base64.decode(payload, Base64.DEFAULT)
                : Uri.decode(payload).getBytes(StandardCharsets.UTF_8);
        pendingLocal = null;
        askWhere(name != null ? name : "download" + extensionFor(mime), mime);
    }

    private static String extensionFor(String mime) {
        String ext = mime == null ? null : MimeTypeMap.getSingleton().getExtensionFromMimeType(mime);
        return ext == null ? "" : "." + ext;
    }

    private void askWhere(String name, String mime) {
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType(mime == null || mime.isEmpty() ? "application/octet-stream" : mime);
        intent.putExtra(Intent.EXTRA_TITLE, name);
        try {
            activity.startActivityForResult(intent, MainActivity.REQ_SAVE_FILE);
        } catch (ActivityNotFoundException e) {
            pendingBytes = null;
            pendingLocal = null;
            activity.toast("这台手机没有可用的“文件”应用，保存不了");
        }
    }

    /** 用户选完保存位置（或取消了）。 */
    void onSaveResult(int resultCode, Intent data) {
        final byte[] bytes = pendingBytes;
        final Uri local = pendingLocal;
        pendingBytes = null;
        pendingLocal = null;
        final Uri target = data == null ? null : data.getData();
        if (resultCode != Activity.RESULT_OK || target == null || (bytes == null && local == null)) {
            return;
        }
        new Thread(new Runnable() {
            @Override
            public void run() {
                String message = "已保存";
                try {
                    InputStream in = bytes != null ? new ByteArrayInputStream(bytes) : activity.server.openLocal(local);
                    if (in == null) {
                        message = "应用里没有这个文件，没有保存";
                    } else {
                        try {
                            OutputStream out = activity.getContentResolver().openOutputStream(target);
                            if (out == null) {
                                message = "选的位置写不进去，没有保存";
                            } else {
                                try {
                                    byte[] buf = new byte[16384];
                                    int n;
                                    while ((n = in.read(buf)) > 0) {
                                        out.write(buf, 0, n);
                                    }
                                } finally {
                                    out.close();
                                }
                            }
                        } finally {
                            in.close();
                        }
                    }
                } catch (Exception e) {
                    message = "保存失败：选的位置写不进去";
                }
                final String shown = message;
                activity.runOnUiThread(new Runnable() {
                    @Override
                    public void run() {
                        activity.toast(shown);
                    }
                });
            }
        }).start();
    }
}
