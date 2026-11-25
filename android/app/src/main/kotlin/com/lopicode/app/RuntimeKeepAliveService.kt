package com.lopicode.app

import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Ubuntu 环境里有东西在跑、或者 Agent 有一轮在跑的时候挂一个前台服务（带常驻通知），
 * 这样切到后台、锁屏不会马上被系统回收。它自己不干活：进程都是应用主进程的子进程，Agent 跑在 Flutter 那头。
 * 通知上显示什么、什么时候该停，都记在 [KeepAliveHub]。
 */
class RuntimeKeepAliveService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == KeepAliveHub.ACTION_STOP_AGENT) {
            // 通知上点了“停止”：交给 Flutter 那头停（和聊天页里点停止是同一条路）
            KeepAliveHub.onStopPressed?.invoke()
            // 正常情况下服务这时已经在前台；万一不是（残留的通知），别留一个空服务
            if (!KeepAliveHub.serviceRunning && !KeepAliveHub.serviceStarting) stopSelf()
            return START_NOT_STICKY
        }
        KeepAliveHub.serviceStarting = false
        val stillWanted = KeepAliveHub.runtimeText != null || KeepAliveHub.agent != null
        try {
            val notification = KeepAliveHub.buildOngoing(this)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                startForeground(KeepAliveHub.ONGOING_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
            } else {
                startForeground(KeepAliveHub.ONGOING_ID, notification)
            }
        } catch (e: RuntimeException) {
            // 系统不让转前台：保活开不了，不影响环境和 Agent 本身
            KeepAliveHub.serviceRunning = false
            stopSelf()
            return START_NOT_STICKY
        }
        if (!stillWanted) {
            // 启动到一半原因已经没了（开了马上又关）：必须先转前台再收，否则系统会判“没按时转前台”
            KeepAliveHub.serviceRunning = false
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        KeepAliveHub.serviceRunning = true
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        KeepAliveHub.serviceRunning = false
        super.onDestroy()
    }
}
