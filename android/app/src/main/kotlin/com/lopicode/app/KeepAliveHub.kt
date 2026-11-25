package com.lopicode.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.os.Build

/**
 * “为什么要留在后台”的账本，和那条常驻通知长什么样。
 *
 * 前台服务只有一个（[RuntimeKeepAliveService]），占用它的原因有两种：
 *  - 运行环境：Ubuntu 里有终端 / 命令 / 安装在跑（原来就有，行为不变）；
 *  - Agent：有一轮对话在跑（新加的）。
 * 两种都有时通知显示 Agent 的进度（它变得快、还带“停止”）；都没有了才停服务。
 *
 * 这里的东西都只在主线程上读写（平台通道的回调、服务和 Activity 的生命周期都在主线程）。
 * 服务只负责“留住进程 + 显示通知”，Agent 本身跑在 Flutter 那头。
 */
object KeepAliveHub {
    const val ACTION_STOP_AGENT = "com.lopicode.app.action.STOP_AGENT"

    private const val CHANNEL_RUNTIME = "runtime"
    private const val CHANNEL_AGENT = "agent_progress"
    private const val CHANNEL_ALERT = "agent_alert"

    const val ONGOING_ID = 4201
    private const val ALERT_DONE_ID = 4202
    private const val ALERT_WAITING_ID = 4203

    private const val REQUEST_OPEN = 0
    private const val REQUEST_STOP = 1

    /** Agent 那条进度：标题、正文（已在 Dart 那头脱敏截短）、锁屏隐藏敏感内容时显示的那一句。 */
    class AgentStatus(val title: String, val text: String, val lockText: String)

    /** 运行环境要保活时通知上的字；null＝运行环境这头不需要。 */
    var runtimeText: String? = null

    /** Agent 的进度；null＝Agent 这头不需要。 */
    var agent: AgentStatus? = null

    /** 服务已经 startForeground 了。 */
    var serviceRunning = false

    /** 已经请系统启动服务、但它的 onStartCommand 还没跑到。这段时间里不能 stopService（系统会判“没按时转前台”而崩）。 */
    var serviceStarting = false

    /** 应用界面现在看不看得见（MainActivity 的 onStart / onStop）。 */
    var appVisible = false

    /** 通知上的“停止”被点了：交给 Flutter 那头去停。Flutter 引擎不在了就是 null。 */
    var onStopPressed: (() -> Unit)? = null

    private val wanted: Boolean get() = runtimeText != null || agent != null

    /**
     * 按账本把服务和通知调到该有的样子。返回 false＝该开却没开成（应用在后台时系统不让开前台服务）。
     */
    fun apply(context: Context): Boolean {
        val app = context.applicationContext
        if (!wanted) {
            // 正在启动的那一下留给服务自己收（见 RuntimeKeepAliveService.onStartCommand）
            if (!serviceStarting) {
                // 先记成“没在跑”：服务的 onDestroy 要晚一拍才到，这中间又要保活的话得重新启动，不能只换字
                serviceRunning = false
                app.stopService(Intent(app, RuntimeKeepAliveService::class.java))
            }
            return true
        }
        if (serviceRunning) {
            // 服务已经在前台：同一个编号再发一次就是换字，不用再走启动服务（后台时那样会被拒）
            return try {
                manager(app).notify(ONGOING_ID, buildOngoing(app))
                true
            } catch (e: RuntimeException) {
                false
            }
        }
        if (serviceStarting) return true // onStartCommand 跑到时会按最新的账本显示
        return try {
            val intent = Intent(app, RuntimeKeepAliveService::class.java)
            serviceStarting = true
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) app.startForegroundService(intent) else app.startService(intent)
            true
        } catch (e: RuntimeException) {
            // Android 12 起应用在后台时不许启动前台服务（ForegroundServiceStartNotAllowedException）
            serviceStarting = false
            false
        }
    }

    /** 常驻通知。账本是空的时候也给一条最简单的（服务启动到一半原因没了，要先转前台再收掉）。 */
    fun buildOngoing(context: Context): Notification {
        ensureChannels(context)
        val status = agent
        val builder = newBuilder(context, if (status != null) CHANNEL_AGENT else CHANNEL_RUNTIME)
            .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
            .setContentIntent(openApp(context))
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setShowWhen(false)
        if (status == null) {
            builder.setContentTitle("LopiCode").setContentText(runtimeText ?: "Ubuntu 环境运行中")
        } else {
            val stop = PendingIntent.getService(
                context, REQUEST_STOP,
                Intent(context, RuntimeKeepAliveService::class.java).setAction(ACTION_STOP_AGENT),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            builder
                .setContentTitle(status.title)
                .setContentText(status.text)
                .setStyle(Notification.BigTextStyle().bigText(status.text))
                .setCategory(Notification.CATEGORY_PROGRESS)
                // 锁屏上：系统设了“隐藏敏感内容”时只显示下面这条不带文件名、命令的版本
                .setVisibility(Notification.VISIBILITY_PRIVATE)
                .setPublicVersion(
                    newBuilder(context, CHANNEL_AGENT)
                        .setSmallIcon(android.R.drawable.stat_notify_sync_noanim)
                        .setContentTitle(status.title)
                        .setContentText(status.lockText)
                        .setShowWhen(false)
                        .build()
                )
                .addAction(
                    Notification.Action.Builder(
                        Icon.createWithResource(context, android.R.drawable.ic_menu_close_clear_cancel), "停止", stop
                    ).build()
                )
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            // Android 12 起前台服务的通知默认会晚 10 秒才出现；这里要它马上出现
            builder.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
        }
        return builder.build()
    }

    /** 发一条“做完了 / 出错了 / 在等你确认”。界面看得见时不发。 */
    fun postAlert(context: Context, kind: String, title: String, text: String, lockText: String) {
        if (appVisible) return
        val app = context.applicationContext
        ensureChannels(app)
        val notification = newBuilder(app, CHANNEL_ALERT)
            .setSmallIcon(android.R.drawable.stat_notify_chat)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(openApp(app))
            .setAutoCancel(true)
            .setVisibility(Notification.VISIBILITY_PRIVATE)
            .setPublicVersion(
                newBuilder(app, CHANNEL_ALERT)
                    .setSmallIcon(android.R.drawable.stat_notify_chat)
                    .setContentTitle(title)
                    .setContentText(lockText)
                    .build()
            )
            .build()
        try {
            manager(app).notify(if (kind == "waiting") ALERT_WAITING_ID else ALERT_DONE_ID, notification)
        } catch (e: RuntimeException) {
            // 发不出去就算了：不影响 Agent
        }
    }

    /** 收掉提醒。kind 为 null＝全部。 */
    fun cancelAlerts(context: Context, kind: String?) {
        val manager = manager(context.applicationContext)
        if (kind == null || kind == "waiting") manager.cancel(ALERT_WAITING_ID)
        if (kind != "waiting") manager.cancel(ALERT_DONE_ID)
    }

    private fun manager(context: Context): NotificationManager = context.getSystemService(NotificationManager::class.java)

    private fun newBuilder(context: Context, channel: String): Notification.Builder =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, channel)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context)
        }

    private fun ensureChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = manager(context)
        // 进度两条都是“低”：不响、不弹；提醒那条是“默认”：会响一下
        manager.createNotificationChannel(NotificationChannel(CHANNEL_RUNTIME, "运行环境", NotificationManager.IMPORTANCE_LOW))
        manager.createNotificationChannel(NotificationChannel(CHANNEL_AGENT, "Agent 进度", NotificationManager.IMPORTANCE_LOW))
        manager.createNotificationChannel(NotificationChannel(CHANNEL_ALERT, "Agent 做完 / 等你确认", NotificationManager.IMPORTANCE_DEFAULT))
    }

    /** 点通知本体：和点桌面图标一样回到应用（已经开着就回到原来那一页）。 */
    private fun openApp(context: Context): PendingIntent {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?: Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            context, REQUEST_OPEN, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }
}
