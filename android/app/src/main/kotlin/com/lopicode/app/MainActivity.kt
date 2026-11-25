package com.lopicode.app

import android.Manifest
import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /** Agent 后台保活的通道（Dart 那头是 lib/agent/keep_alive_host.dart）。引擎没了就是 null。 */
    private var agentChannel: MethodChannel? = null

    /** 这次运行里已经为 Agent 问过一次通知权限（免得每一轮都弹）。 */
    private var askedForAgent = false

    /** 选背景图片的通道（系统选择器，不要权限；见 BackdropPicker.kt）。 */
    private var backdropPicker: BackdropPicker? = null

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
                    KeepAliveHub.runtimeText = (call.arguments as? String) ?: "Ubuntu 环境运行中"
                    if (KeepAliveHub.apply(this)) {
                        result.success(null)
                    } else {
                        // 应用在后台时系统不让启动前台服务：保活开不了，但不影响环境本身。
                        result.error("keep_alive", "系统不允许现在启动前台服务", null)
                    }
                }
                "stopKeepAlive" -> {
                    KeepAliveHub.runtimeText = null
                    KeepAliveHub.apply(this)
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

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lopicode/agent_keepalive")
        agentChannel = channel
        channel.setMethodCallHandler { call, result -> onAgentCall(call, result) }
        KeepAliveHub.onStopPressed = { agentChannel?.invokeMethod("stopPressed", null) }
        backdropPicker = BackdropPicker(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        // 选背景图片的结果在这里收；不是它的照旧交给上层（别的插件要用）。
        if (backdropPicker?.onActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        // Flutter 引擎没了，Agent 也就不在跑了：把 Agent 这头的保活撤掉（运行环境那头照旧）。
        KeepAliveHub.onStopPressed = null
        backdropPicker?.dispose()
        backdropPicker = null
        agentChannel?.setMethodCallHandler(null)
        agentChannel = null
        KeepAliveHub.agent = null
        KeepAliveHub.apply(this)
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onStart() {
        super.onStart()
        KeepAliveHub.appVisible = true
        // 人已经回到应用里：做完 / 等确认的提醒不用再挂着
        KeepAliveHub.cancelAlerts(this, null)
        agentChannel?.invokeMethod("visible", true)
    }

    override fun onStop() {
        KeepAliveHub.appVisible = false
        agentChannel?.invokeMethod("visible", false)
        super.onStop()
    }

    private fun onAgentCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start", "update" -> {
                val status = agentStatusOf(call)
                if (status == null) {
                    result.error("bad_args", "缺少 title / text", null)
                    return
                }
                if (call.method == "start" && !askedForAgent) {
                    askedForAgent = true
                    askNotificationPermission()
                }
                KeepAliveHub.agent = status
                result.success(KeepAliveHub.apply(this))
            }
            "stop" -> {
                KeepAliveHub.agent = null
                KeepAliveHub.apply(this)
                result.success(null)
            }
            "alert" -> {
                val kind = call.argument<String>("kind")
                val title = call.argument<String>("title")
                if (kind != null && title != null) {
                    KeepAliveHub.postAlert(this, kind, title, call.argument<String>("text") ?: "", call.argument<String>("lockText") ?: "")
                }
                result.success(null)
            }
            "cancelAlerts" -> {
                KeepAliveHub.cancelAlerts(this, call.arguments as? String)
                result.success(null)
            }
            "notificationsAllowed" -> result.success(getSystemService(NotificationManager::class.java).areNotificationsEnabled())
            "requestNotifications" -> {
                askNotificationPermission()
                result.success(null)
            }
            "openNotificationSettings" -> {
                val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                } else {
                    appDetailsIntent()
                }
                result.success(tryStart(intent))
            }
            "openAppSettings" -> result.success(tryStart(appDetailsIntent()))
            else -> result.notImplemented()
        }
    }

    private fun agentStatusOf(call: MethodCall): KeepAliveHub.AgentStatus? {
        val title = call.argument<String>("title") ?: return null
        val text = call.argument<String>("text") ?: return null
        return KeepAliveHub.AgentStatus(title, text, call.argument<String>("lockText") ?: "")
    }

    private fun appDetailsIntent(): Intent =
        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))

    private fun tryStart(intent: Intent): Boolean =
        try {
            startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
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
