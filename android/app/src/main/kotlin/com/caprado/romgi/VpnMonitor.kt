package com.caprado.romgi

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class VpnMonitor(context: Context, messenger: BinaryMessenger) {
    private val connectivity =
        context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    init {
        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "isVpnActive") result.success(isVpnActive())
            else result.notImplemented()
        }
        EventChannel(messenger, EVENT_CHANNEL).setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                sink = events
                events.success(isVpnActive())
                register()
            }

            override fun onCancel(arguments: Any?) {
                unregister()
                sink = null
            }
        })
    }

    fun isVpnActive(): Boolean {
        val network = connectivity.activeNetwork ?: return false
        val caps = connectivity.getNetworkCapabilities(network) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_VPN)
    }

    private fun register() {
        if (callback != null) return
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) = emit()
            override fun onLost(network: Network) = emit()
            override fun onAvailable(network: Network) = emit()
        }
        connectivity.registerDefaultNetworkCallback(cb)
        callback = cb
    }

    private fun unregister() {
        callback?.let { runCatching { connectivity.unregisterNetworkCallback(it) } }
        callback = null
    }

    private fun emit() {
        val active = isVpnActive()
        main.post { sink?.success(active) }
    }

    fun dispose() {
        unregister()
        sink = null
    }

    companion object {
        private const val METHOD_CHANNEL = "com.caprado.romgi/network"
        private const val EVENT_CHANNEL = "com.caprado.romgi/vpn"
    }
}
