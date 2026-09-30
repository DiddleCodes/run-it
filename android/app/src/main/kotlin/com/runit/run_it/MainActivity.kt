package com.runit.run_it

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterFragmentActivity

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createOrdersChannel()
    }

    // Push notifications (order updates) land on this channel — the backend
    // names it in every send (FcmService), and the manifest makes it the
    // default. High importance so they sound and show as a heads-up, not
    // silently in the shade. Re-creating an existing channel is a no-op.
    private fun createOrdersChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            ORDERS_CHANNEL_ID,
            "Order updates",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply { description = "When your order is accepted, picked up or delivered." }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        // Must match ANDROID_ORDERS_CHANNEL_ID in backend/src/notifications/fcm.service.ts.
        const val ORDERS_CHANNEL_ID = "orders"
    }
}
