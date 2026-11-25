package lopi.shell;

import android.app.AlertDialog;
import android.content.DialogInterface;
import android.graphics.Bitmap;
import android.net.Uri;
import android.view.View;
import android.webkit.GeolocationPermissions;
import android.webkit.JsPromptResult;
import android.webkit.JsResult;
import android.webkit.PermissionRequest;
import android.webkit.ValueCallback;
import android.webkit.WebChromeClient;
import android.webkit.WebView;
import android.widget.EditText;
import android.widget.FrameLayout;

/** 网页的弹窗（alert / confirm / prompt）、选文件、全屏视频、摄像头 / 麦克风 / 定位申请。 */
final class ShellChromeClient extends WebChromeClient {
    private final MainActivity activity;

    ShellChromeClient(MainActivity activity) {
        this.activity = activity;
    }

    // ── 弹窗：自己画，免得标题显示成“位于 https://lopi.invalid 的网页显示” ──

    private boolean cannotShow(JsResult result) {
        if (activity.isFinishing() || activity.isDestroyed()) {
            result.cancel();
            return true;
        }
        return false;
    }

    @Override
    public boolean onJsAlert(WebView view, String url, String message, final JsResult result) {
        if (cannotShow(result)) {
            return true;
        }
        new AlertDialog.Builder(activity)
                .setMessage(message)
                .setPositiveButton("确定", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        result.confirm();
                    }
                })
                .setOnCancelListener(new DialogInterface.OnCancelListener() {
                    @Override
                    public void onCancel(DialogInterface dialog) {
                        result.cancel();
                    }
                })
                .show();
        return true;
    }

    @Override
    public boolean onJsConfirm(WebView view, String url, String message, JsResult result) {
        return confirm(message, "确定", "取消", result);
    }

    @Override
    public boolean onJsBeforeUnload(WebView view, String url, String message, JsResult result) {
        return confirm("离开这个页面吗？还没保存的内容可能会丢。", "离开", "留下", result);
    }

    private boolean confirm(String message, String yes, String no, final JsResult result) {
        if (cannotShow(result)) {
            return true;
        }
        new AlertDialog.Builder(activity)
                .setMessage(message)
                .setPositiveButton(yes, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        result.confirm();
                    }
                })
                .setNegativeButton(no, new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        result.cancel();
                    }
                })
                .setOnCancelListener(new DialogInterface.OnCancelListener() {
                    @Override
                    public void onCancel(DialogInterface dialog) {
                        result.cancel();
                    }
                })
                .show();
        return true;
    }

    @Override
    public boolean onJsPrompt(WebView view, String url, String message, String defaultValue, final JsPromptResult result) {
        if (cannotShow(result)) {
            return true;
        }
        final EditText input = new EditText(activity);
        input.setSingleLine(true);
        if (defaultValue != null) {
            input.setText(defaultValue);
            input.setSelection(defaultValue.length());
        }
        FrameLayout box = new FrameLayout(activity);
        int pad = (int) (20 * activity.getResources().getDisplayMetrics().density);
        box.setPadding(pad, pad / 2, pad, 0);
        box.addView(input);
        new AlertDialog.Builder(activity)
                .setMessage(message)
                .setView(box)
                .setPositiveButton("确定", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        result.confirm(input.getText().toString());
                    }
                })
                .setNegativeButton("取消", new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialog, int which) {
                        result.cancel();
                    }
                })
                .setOnCancelListener(new DialogInterface.OnCancelListener() {
                    @Override
                    public void onCancel(DialogInterface dialog) {
                        result.cancel();
                    }
                })
                .show();
        return true;
    }

    // ── 权限 ──

    @Override
    public void onPermissionRequest(PermissionRequest request) {
        activity.permissions.onWebRequest(request);
    }

    @Override
    public void onPermissionRequestCanceled(PermissionRequest request) {
        activity.permissions.onWebRequestCanceled(request);
    }

    @Override
    public void onGeolocationPermissionsShowPrompt(String origin, GeolocationPermissions.Callback callback) {
        activity.permissions.onGeo(origin, callback);
    }

    @Override
    public void onGeolocationPermissionsHidePrompt() {
        activity.permissions.onGeoHide();
    }

    // ── 选文件、全屏 ──

    @Override
    public boolean onShowFileChooser(WebView view, ValueCallback<Uri[]> callback, FileChooserParams params) {
        return activity.pickFiles(callback, params);
    }

    @Override
    public void onShowCustomView(View view, CustomViewCallback callback) {
        activity.enterFullscreen(view, callback);
    }

    @Override
    public void onHideCustomView() {
        activity.exitFullscreen();
    }

    @Override
    public Bitmap getDefaultVideoPoster() {
        // 不给的话，视频没加载出来时会显示一个灰色的大播放图标。
        return Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888);
    }
}
