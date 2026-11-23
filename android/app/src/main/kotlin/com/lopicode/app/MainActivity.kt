package com.lopicode.app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.StatFs
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lopicode/runtime").setMethodCallHandler { call, result ->
            when (call.method) {
                // 安装包自带的原生库目录：PRoot 只能从这里执行。
                "nativeLibraryDir" -> result.success(applicationInfo.nativeLibraryDir)
                "freeBytes" -> {
                    val path = (call.arguments as? String) ?: filesDir.path
                    try {
                        result.success(StatFs(path).availableBytes)
                    } catch (e: IllegalArgumentException) {
                        result.success(null)
                    }
                }
                "startKeepAlive" -> {
                    askNotificationPermission()
                    val intent = Intent(this, RuntimeKeepAliveService::class.java)
                        .putExtra(RuntimeKeepAliveService.EXTRA_TEXT, call.arguments as? String)
                    try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent) else startService(intent)
                        result.success(null)
                    } catch (e: RuntimeException) {
                        // 应用在后台时系统不让启动前台服务：保活开不了，但不影响环境本身。
                        result.error("keep_alive", e.message, null)
                    }
                }
                "stopKeepAlive" -> {
                    stopService(Intent(this, RuntimeKeepAliveService::class.java))
                    result.success(null)
                }
                // 诊断用：手机型号和系统版本。不含任何账号、密钥。
                "deviceInfo" -> result.success(
                    mapOf(
                        "手机" to "${Build.MANUFACTURER} ${Build.MODEL}",
                        "Android" to "${Build.VERSION.RELEASE}（API ${Build.VERSION.SDK_INT}）",
                        "系统版本号" to Build.DISPLAY,
                        "处理器架构" to Build.SUPPORTED_ABIS.joinToString(","),
                        "应用目标版本" to "API ${applicationInfo.targetSdkVersion}",
                        "原生库目录" to applicationInfo.nativeLibraryDir,
                    ),
                )
                else -> result.notImplemented()
            }
        }
    }

    /** Android 13 起，通知要用户点头才显示；不点头服务照样跑，只是看不到常驻通知。 */
    private fun askNotificationPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1001)
        }
    }
}
