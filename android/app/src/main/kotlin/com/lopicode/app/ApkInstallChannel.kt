package com.lopicode.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

/**
 * 应用内安装 APK 的通道（Dart 那头是 lib/build/apk_installer.dart）。
 *
 * 只做三件事：问系统“现在让不让我们发起安装”、打开“允许安装未知应用”的设置页、把一个安装包交给系统安装器。
 * 装没装成是系统安装器的事，这里拿不到结果，也不假装知道。官方文档的核对记录见 docs/api-notes.md。
 */
object ApkInstallChannel {
    private const val NAME = "lopicode/apk_install"
    private const val APK_MIME = "application/vnd.android.package-archive"

    /** 清单里 provider 的 authorities 是 `${applicationId}.apkinstall`，这里要拼成一样的。 */
    private fun authority(activity: Activity) = "${activity.packageName}.apkinstall"

    /** 配置的目录里找不到这个文件时，先抄到这里再交出去（res/xml/apk_install_paths.xml 里登记了它）。 */
    private const val STAGE_DIR = "apk_install"

    fun attach(activity: Activity, messenger: BinaryMessenger) {
        MethodChannel(messenger, NAME).setMethodCallHandler { call, result ->
            when (call.method) {
                "canInstall" -> result.success(canInstall(activity))
                "openInstallSettings" -> result.success(openSettings(activity))
                "install" -> {
                    val path = call.arguments as? String
                    if (path == null) {
                        result.error("bad_args", "缺少文件路径", null)
                    } else {
                        // 可能要先抄一份（大文件要几秒），放到后台线程；拉起安装器回到主线程。
                        Thread {
                            val prepared = prepare(activity, path)
                            activity.runOnUiThread { result.success(launch(activity, prepared)) }
                        }.start()
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /** Android 8 以前没有“按应用允许”这回事；8 起要用户在设置里给这个应用单独打开。 */
    private fun canInstall(activity: Activity): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.O || activity.packageManager.canRequestPackageInstalls()

    private fun openSettings(activity: Activity): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val forApp = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.fromParts("package", activity.packageName, null))
        // 有的系统不认带包名的写法：退一步打开总列表。
        return tryStart(activity, forApp) || tryStart(activity, Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES))
    }

    private fun tryStart(activity: Activity, intent: Intent): Boolean =
        try {
            activity.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        }

    private class Prepared(val status: String, val uri: Uri? = null, val staged: Boolean = false)

    private fun prepare(activity: Activity, path: String): Prepared {
        val file = File(path)
        if (!file.isFile) return Prepared("missing")
        if (!file.canRead()) return Prepared("unreadable")
        if (!canInstall(activity)) return Prepared("need_permission")
        return try {
            Prepared("ok", FileProvider.getUriForFile(activity, authority(activity), file))
        } catch (e: IllegalArgumentException) {
            // 不在登记的目录里（比如 Ubuntu 环境里的工作区）：抄一份到缓存目录再交出去。
            try {
                val dir = File(activity.cacheDir, STAGE_DIR)
                dir.deleteRecursively() // 只留这一次的，上一次抄的不留
                dir.mkdirs()
                val copy = File(dir, file.name)
                file.copyTo(copy, overwrite = true)
                Prepared("ok", FileProvider.getUriForFile(activity, authority(activity), copy), staged = true)
            } catch (io: IOException) {
                Prepared("copy_failed")
            } catch (again: IllegalArgumentException) {
                Prepared("not_shareable")
            }
        }
    }

    private fun launch(activity: Activity, prepared: Prepared): Map<String, Any> {
        val uri = prepared.uri ?: return mapOf("status" to prepared.status, "staged" to false)
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        val status = try {
            activity.startActivity(intent)
            "launched"
        } catch (e: ActivityNotFoundException) {
            "no_installer"
        } catch (e: SecurityException) {
            "blocked"
        }
        return mapOf("status" to status, "staged" to prepared.staged)
    }
}
