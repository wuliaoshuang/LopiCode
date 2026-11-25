package lopi.shell;

import android.Manifest;
import android.content.pm.PackageInfo;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.webkit.GeolocationPermissions;
import android.webkit.PermissionRequest;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.Set;

/**
 * 网页要摄像头、麦克风、定位时怎么办。规则只有一条：
 * 安装包的清单里声明了对应权限，才向用户申请并转给网页；没声明就直接拒绝，不弹窗、不崩。
 * 只答应应用自己的网页（本地地址），嵌进来的外部网站一律拒绝。
 */
final class Permissions {
    private final MainActivity activity;
    private final Set<String> declared = new HashSet<String>();

    private PermissionRequest webRequest;
    private String[] webResources;
    private String geoOrigin;
    private GeolocationPermissions.Callback geoCallback;

    Permissions(MainActivity activity) {
        this.activity = activity;
        try {
            PackageInfo info = activity.getPackageManager()
                    .getPackageInfo(activity.getPackageName(), PackageManager.GET_PERMISSIONS);
            if (info.requestedPermissions != null) {
                for (String p : info.requestedPermissions) {
                    declared.add(p);
                }
            }
        } catch (Exception e) {
            // 查不到自己的清单（理论上不会）：当作什么权限都没声明，网页的申请全部拒绝。
        }
    }

    private boolean granted(String permission) {
        return activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED;
    }

    private boolean busy() {
        return webRequest != null || geoCallback != null;
    }

    private static String androidPermissionFor(String webResource) {
        if (PermissionRequest.RESOURCE_VIDEO_CAPTURE.equals(webResource)) {
            return Manifest.permission.CAMERA;
        }
        if (PermissionRequest.RESOURCE_AUDIO_CAPTURE.equals(webResource)) {
            return Manifest.permission.RECORD_AUDIO;
        }
        return null;
    }

    /** 网页申请摄像头 / 麦克风。 */
    void onWebRequest(PermissionRequest request) {
        if (!AssetServer.isLocal(request.getOrigin())) {
            request.deny();
            return;
        }
        ArrayList<String> resources = new ArrayList<String>();
        ArrayList<String> missing = new ArrayList<String>();
        for (String res : request.getResources()) {
            String p = androidPermissionFor(res);
            if (p != null && declared.contains(p)) {
                resources.add(res);
                if (!granted(p)) {
                    missing.add(p);
                }
            }
        }
        if (resources.isEmpty()) {
            request.deny();
            return;
        }
        String[] wanted = resources.toArray(new String[0]);
        if (missing.isEmpty()) {
            request.grant(wanted);
            return;
        }
        if (busy()) {
            request.deny(); // 系统一次只能弹一个权限窗
            return;
        }
        webRequest = request;
        webResources = wanted;
        activity.requestPermissions(missing.toArray(new String[0]), MainActivity.REQ_WEB_PERMISSION);
    }

    void onWebRequestCanceled(PermissionRequest request) {
        if (webRequest == request) {
            webRequest = null;
            webResources = null;
        }
    }

    /** 网页申请定位。 */
    void onGeo(String origin, GeolocationPermissions.Callback callback) {
        boolean fine = declared.contains(Manifest.permission.ACCESS_FINE_LOCATION);
        boolean coarse = declared.contains(Manifest.permission.ACCESS_COARSE_LOCATION);
        if (origin == null || !AssetServer.isLocal(Uri.parse(origin)) || !(fine || coarse)) {
            callback.invoke(origin, false, false);
            return;
        }
        if ((fine && granted(Manifest.permission.ACCESS_FINE_LOCATION))
                || (coarse && granted(Manifest.permission.ACCESS_COARSE_LOCATION))) {
            callback.invoke(origin, true, false);
            return;
        }
        if (busy()) {
            callback.invoke(origin, false, false);
            return;
        }
        geoOrigin = origin;
        geoCallback = callback;
        ArrayList<String> ask = new ArrayList<String>();
        if (fine) {
            ask.add(Manifest.permission.ACCESS_FINE_LOCATION);
        }
        if (coarse) {
            ask.add(Manifest.permission.ACCESS_COARSE_LOCATION);
        }
        activity.requestPermissions(ask.toArray(new String[0]), MainActivity.REQ_GEO_PERMISSION);
    }

    void onGeoHide() {
        geoOrigin = null;
        geoCallback = null;
    }

    /** 用户在系统权限窗里点完了。不看回调带的数组（可能是空的），直接重新查一遍实际状态。 */
    void onResult(int requestCode) {
        if (requestCode == MainActivity.REQ_WEB_PERMISSION && webRequest != null) {
            PermissionRequest request = webRequest;
            String[] resources = webResources;
            webRequest = null;
            webResources = null;
            ArrayList<String> ok = new ArrayList<String>();
            for (String res : resources) {
                if (granted(androidPermissionFor(res))) {
                    ok.add(res);
                }
            }
            if (ok.isEmpty()) {
                request.deny();
            } else {
                request.grant(ok.toArray(new String[0]));
            }
        } else if (requestCode == MainActivity.REQ_GEO_PERMISSION && geoCallback != null) {
            GeolocationPermissions.Callback callback = geoCallback;
            String origin = geoOrigin;
            geoCallback = null;
            geoOrigin = null;
            boolean ok = granted(Manifest.permission.ACCESS_FINE_LOCATION)
                    || granted(Manifest.permission.ACCESS_COARSE_LOCATION);
            callback.invoke(origin, ok, false);
        }
    }
}
