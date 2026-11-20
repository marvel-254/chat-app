package com.omixsystems.pulsechat

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/** Started only after foreground mic/camera consent, never from an FCM callback. */
class CallCaptureService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val channel = "ongoing_calls"
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(channel, "Ongoing calls", NotificationManager.IMPORTANCE_LOW))
            Notification.Builder(this, channel)
        } else Notification.Builder(this)
        val tap = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val note = builder.setSmallIcon(R.mipmap.ic_launcher).setContentTitle("BRO call in progress").setContentText("Tap to return to BRO").setContentIntent(tap).setOngoing(true).build()
        if (Build.VERSION.SDK_INT >= 30) {
            val type = ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or (if (intent?.getBooleanExtra("video", false) == true) ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA else 0)
            startForeground(301, note, type)
        } else startForeground(301, note)
        return START_NOT_STICKY
    }
}
