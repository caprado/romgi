package com.caprado.romgi

import android.content.Intent
import android.webkit.CookieManager
import androidx.core.content.FileProvider
import com.caprado.romgi.seven_zip.SevenZipHostApi
import com.caprado.romgi.seven_zip.SevenZipServiceImpl
import com.caprado.romgi.torrent.TorrentHostApi
import com.caprado.romgi.torrent.TorrentServiceImpl
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private var torrentService: TorrentServiceImpl? = null
    private var vpnMonitor: VpnMonitor? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val service = TorrentServiceImpl(
            applicationContext,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        torrentService = service
        TorrentHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, service)

        val sevenZipService = SevenZipServiceImpl(
            flutterEngine.dartExecutor.binaryMessenger,
        )
        SevenZipHostApi.setUp(flutterEngine.dartExecutor.binaryMessenger, sevenZipService)

        vpnMonitor = VpnMonitor(applicationContext, flutterEngine.dartExecutor.binaryMessenger)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, OPEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "openWithChooser") {
                    val path = call.argument<String>("path")
                    if (path == null) {
                        result.error("ARG", "path is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        val uri = FileProvider.getUriForFile(
                            this, "$packageName.fileprovider", file,
                        )
                        // ACTION_VIEW + createChooser forces the system
                        // app picker every time, ignoring the user's
                        // saved default for this MIME type.
                        val view = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "*/*")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        val chooser = Intent.createChooser(view, "Open with").apply {
                            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        }
                        startActivity(chooser)
                        result.success(null)
                    } catch (t: Throwable) {
                        result.error("OPEN_FAILED", t.message, null)
                    }
                } else if (call.method == "getWebViewCookies") {
                    val url = call.argument<String>("url")
                    if (url == null) {
                        result.error("ARG", "url is required", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val cookies = CookieManager.getInstance().getCookie(url) ?: ""
                        result.success(cookies)
                    } catch (t: Throwable) {
                        result.error("COOKIE_FAILED", t.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        torrentService?.shutdown()
        torrentService = null
        vpnMonitor?.dispose()
        vpnMonitor = null
        super.onDestroy()
    }

    companion object {
        private const val OPEN_CHANNEL = "com.caprado.romgi/open"
    }
}
