package com.caprado.romgi.torrent

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.libtorrent4j.AddTorrentParams
import org.libtorrent4j.AlertListener
import org.libtorrent4j.Priority
import org.libtorrent4j.SessionManager
import org.libtorrent4j.SessionParams
import org.libtorrent4j.SettingsPack
import org.libtorrent4j.Sha1Hash
import org.libtorrent4j.TorrentHandle
import org.libtorrent4j.TorrentInfo
import org.libtorrent4j.TorrentStatus
import org.libtorrent4j.alerts.Alert
import org.libtorrent4j.alerts.AlertType
import org.libtorrent4j.alerts.ListenFailedAlert
import org.libtorrent4j.alerts.ListenSucceededAlert
import org.libtorrent4j.alerts.MetadataReceivedAlert
import org.libtorrent4j.alerts.TorrentErrorAlert
import org.libtorrent4j.alerts.TorrentFinishedAlert
import org.libtorrent4j.alerts.TrackerAnnounceAlert
import org.libtorrent4j.alerts.TrackerErrorAlert
import org.libtorrent4j.alerts.TrackerReplyAlert
import io.flutter.plugin.common.BinaryMessenger
import java.io.File
import java.util.Collections
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

/**
 * Wraps a [SessionManager] and surfaces it through [TorrentHostApi].
 * One session per app process. [start] is idempotent.
 */
private const val TAG = "TorrentService"

class TorrentServiceImpl(
    @Suppress("unused") private val context: Context,
    binaryMessenger: BinaryMessenger,
) : TorrentHostApi {

    private val events = TorrentEvents(binaryMessenger)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val knownInfohashes: MutableSet<String> =
        Collections.newSetFromMap(ConcurrentHashMap())

    // File indices the user actually wants per torrent. Magnet adds
    // can't apply priorities until metadata arrives — we replay these
    // when MetadataReceivedAlert fires.
    private val pendingPriorities: MutableMap<String, List<Long>> =
        ConcurrentHashMap()

    private val pollingExecutor: ScheduledExecutorService =
        Executors.newSingleThreadScheduledExecutor { r ->
            Thread(r, "torrent-poll").apply { isDaemon = true }
        }
    private var pollFuture: ScheduledFuture<*>? = null

    @Volatile private var session: SessionManager? = null
    @Volatile private var currentSettings: TorrentSettings? = null

    // --- Lifecycle --------------------------------------------------------

    @Synchronized
    override fun start(settings: TorrentSettings) {
        val existing = session
        if (existing != null) {
            updateSettings(settings)
            return
        }
        currentSettings = settings
        File(settings.savePath).mkdirs()

        Log.i(TAG, "starting session, savePath=${settings.savePath} dht=${settings.dhtEnabled} seeding=${settings.seedingEnabled}")
        try {
            // SessionManager.start() opens listen sockets via JNI.
            // Running that from Pigeon's main-thread handler trips
            // Android's main-thread network policy and bind() returns
            // EACCES. Doing the start on a worker thread and joining
            // keeps the API synchronous from Dart's perspective while
            // sidestepping the policy check.
            val sm = SessionManager()
            val initError = arrayOfNulls<Throwable>(1)
            val initThread = Thread({
                try {
                    sm.addListener(alertListener)
                    sm.start(SessionParams(buildSettingsPack(settings)))
                    // SessionManager.start() unconditionally applies a
                    // 2 MiB max_metadata_size. Re-apply our settings
                    // afterwards so our 32 MiB ceiling sticks.
                    sm.applySettings(buildSettingsPack(settings))
                } catch (t: Throwable) {
                    initError[0] = t
                }
            }, "torrent-init")
            initThread.start()
            initThread.join()
            initError[0]?.let { throw it }
            session = sm
            Log.i(TAG, "session started")
        } catch (t: Throwable) {
            Log.e(TAG, "failed to start session", t)
            throw t
        }

        pollFuture = pollingExecutor.scheduleAtFixedRate(
            ::emitProgressSnapshot, 1, 1, TimeUnit.SECONDS
        )
    }

    @Synchronized
    override fun updateSettings(settings: TorrentSettings) {
        currentSettings = settings
        val sm = session ?: return
        sm.applySettings(buildSettingsPack(settings))
    }

    // --- Add / cancel ----------------------------------------------------

    @Synchronized
    override fun addTorrent(request: AddTorrentRequest): String {
        val sm = requireSession()
        val saveDir = File(requireNotNull(currentSettings).savePath).apply { mkdirs() }

        val infohash: String
        val handle: TorrentHandle?

        val magnet = request.magnet
        val bytes = request.torrentBytes

        when {
            magnet != null && magnet.isNotBlank() -> {
                val parsed = AddTorrentParams.parseMagnetUri(magnet)
                infohash = parsed.infoHashes.v1.toHex().lowercase()
                if (sm.find(Sha1Hash.parseHex(infohash)) == null) {
                    sm.download(magnet, saveDir, org.libtorrent4j.swig.torrent_flags_t())
                }
                handle = sm.find(Sha1Hash.parseHex(infohash))
            }
            bytes != null && bytes.isNotEmpty() -> {
                val info = TorrentInfo.bdecode(bytes)
                infohash = info.infoHash().toHex().lowercase()
                if (sm.find(Sha1Hash.parseHex(infohash)) == null) {
                    sm.download(info, saveDir)
                }
                handle = sm.find(Sha1Hash.parseHex(infohash))
            }
            else -> throw IllegalArgumentException(
                "AddTorrentRequest needs either a magnet or torrentBytes"
            )
        }

        knownInfohashes += infohash
        if (request.fileIndices.isNotEmpty()) {
            pendingPriorities[infohash] = request.fileIndices
        }
        // Best-effort immediate apply (works when metadata is already on
        // disk from a prior session); the metadata-received alert is
        // what actually completes this for fresh magnets.
        handle?.let { applyFilePriorities(it, request.fileIndices) }

        Log.i(
            TAG,
            "added torrent infohash=$infohash files=${request.fileIndices} " +
                "hasMetadata=${handle?.torrentFile() != null}"
        )
        return infohash
    }

    @Synchronized
    override fun cancel(infohash: String) {
        val sm = session ?: return
        val handle = sm.find(Sha1Hash.parseHex(infohash)) ?: return
        // Partial files stay on disk so the user can resume by re-adding.
        sm.remove(handle)
        knownInfohashes -= infohash
    }

    @Synchronized
    override fun pauseAll() {
        session?.pause()
    }

    @Synchronized
    override fun resumeAll() {
        session?.resume()
    }

    override fun listAll(): List<TorrentProgress> {
        val sm = session ?: return emptyList()
        return knownInfohashes.mapNotNull { ih ->
            sm.find(Sha1Hash.parseHex(ih))?.let(::buildProgress)
        }
    }

    // --- Internals -------------------------------------------------------

    private val alertListener = object : AlertListener {
        // Returning null subscribes to every alert type. The previous
        // explicit list silently dropped some alerts on release builds,
        // and using -1 as an "all" sentinel is wrong: the dispatcher uses
        // each value as a direct array index into its 97-slot
        // listener table, so -1 throws ArrayIndexOutOfBounds.
        override fun types(): IntArray? = null

        override fun alert(alert: Alert<*>) {
            when (alert.type()) {
                AlertType.SESSION_ERROR -> {
                    Log.w(TAG, "session error: ${alert.message()}")
                }
                AlertType.TORRENT_FINISHED -> {
                    // Seeding intentionally disabled: always pause on
                    // finish so we don't upload after the user's file
                    // is in their library.
                    val a = alert as TorrentFinishedAlert
                    a.handle().pause()
                }
                AlertType.TORRENT_ERROR -> {
                    val a = alert as TorrentErrorAlert
                    val ih = a.handle().infoHash().toHex().lowercase()
                    val msg = a.message()
                    Log.w(TAG, "torrent error infohash=$ih msg=$msg")
                    mainHandler.post {
                        events.onError(ih, msg) { /* fire-and-forget */ }
                    }
                }
                AlertType.METADATA_RECEIVED -> {
                    val a = alert as MetadataReceivedAlert
                    val ih = a.handle().infoHash().toHex().lowercase()
                    Log.i(TAG, "metadata received infohash=$ih")
                    val wanted = pendingPriorities.remove(ih) ?: return
                    applyFilePriorities(a.handle(), wanted)
                }
                AlertType.TRACKER_ANNOUNCE -> {
                    val a = alert as TrackerAnnounceAlert
                    Log.d(TAG, "tracker announce url=${a.trackerUrl()}")
                }
                AlertType.TRACKER_REPLY -> {
                    val a = alert as TrackerReplyAlert
                    Log.i(TAG, "tracker reply url=${a.trackerUrl()} peers=${a.numPeers()}")
                }
                AlertType.TRACKER_ERROR -> {
                    val a = alert as TrackerErrorAlert
                    Log.w(TAG, "tracker error url=${a.trackerUrl()} msg=${a.message()}")
                }
                AlertType.DHT_BOOTSTRAP -> {
                    Log.i(TAG, "DHT bootstrapped")
                }
                AlertType.LISTEN_SUCCEEDED -> {
                    val a = alert as ListenSucceededAlert
                    Log.i(TAG, "listen succeeded address=${a.address()} port=${a.port()} socket=${a.socketType()}")
                }
                AlertType.LISTEN_FAILED -> {
                    val a = alert as ListenFailedAlert
                    Log.w(TAG, "listen FAILED ${a.message()}")
                }
                else -> {}
            }
        }
    }

    @Synchronized
    private fun emitProgressSnapshot() {
        val sm = session ?: return
        for (ih in knownInfohashes.toList()) {
            val handle = sm.find(Sha1Hash.parseHex(ih)) ?: continue
            val progress = try {
                buildProgress(handle)
            } catch (e: Exception) {
                Log.w(TAG, "buildProgress failed for $ih, removing: ${e.message}")
                knownInfohashes -= ih
                continue
            }
            // Periodic heartbeat so we can see in logcat that polling is
            // alive and what state libtorrent is in for each torrent.
            Log.d(
                TAG,
                "tick infohash=$ih state=${progress.state} " +
                    "peers=${progress.peers} seeds=${progress.seeds} " +
                    "down=${progress.bytesDownloaded}/${progress.totalSize} " +
                    "rate=${progress.downloadRate}B/s"
            )
            mainHandler.post {
                events.onProgress(progress) { /* fire-and-forget */ }
            }
        }
    }

    private fun buildProgress(handle: TorrentHandle): TorrentProgress {
        val status = handle.status()
        val info = handle.torrentFile()
        val perFileBytes: LongArray? = runCatching { handle.fileProgress() }.getOrNull()
        val files = if (info != null) {
            (0 until info.numFiles()).map { i ->
                val priority = handle.filePriority(i)
                TorrentFile(
                    index = i.toLong(),
                    path = info.files().filePath(i),
                    length = info.files().fileSize(i),
                    bytesDownloaded = perFileBytes?.getOrNull(i) ?: 0L,
                    priority = priorityToInt(priority).toLong(),
                )
            }
        } else emptyList()

        return TorrentProgress(
            infohash = handle.infoHash().toHex().lowercase(),
            name = status.name() ?: "",
            state = stateToString(status.state()),
            totalSize = info?.totalSize() ?: status.totalDone(),
            bytesDownloaded = status.totalDone(),
            downloadRate = status.downloadRate().toLong(),
            uploadRate = status.uploadRate().toLong(),
            peers = status.numPeers().toLong(),
            seeds = status.numSeeds().toLong(),
            error = "",
            files = files,
        )
    }

    private fun applyFilePriorities(handle: TorrentHandle, requestedIndices: List<Long>) {
        val info = handle.torrentFile() ?: return
        val n = info.numFiles()
        // Priority.DEFAULT is libtorrent's actual default download
        // priority (value 4). Priority.LOW is value 1 — lower than
        // default.
        if (requestedIndices.isEmpty()) {
            for (i in 0 until n) handle.filePriority(i, Priority.DEFAULT)
            return
        }
        // Exclusive selection: download only files in `wanted`, skip
        // everything else. Without IGNORE on unwanted files, libtorrent
        // downloads the entire torrent, which on archive.org bundles
        // (multi-TB, thousands of files) means the requested file's
        // pieces never get scheduled and the UI sits at 0%.
        val wanted = requestedIndices.map { it.toInt() }.toSet()
        for (i in 0 until n) {
            handle.filePriority(i, if (i in wanted) Priority.DEFAULT else Priority.IGNORE)
        }
    }

    private fun requireSession(): SessionManager =
        session ?: error("TorrentService not started. Call start() first.")

    private fun buildSettingsPack(s: TorrentSettings): SettingsPack {
        val pack = SettingsPack()
            .connectionsLimit(s.maxConnections.toInt())
            .uploadRateLimit(s.maxUploadRateBytesPerSec.toInt())
            .downloadRateLimit(s.maxDownloadRateBytesPerSec.toInt())
        pack.setInteger(
            org.libtorrent4j.swig.settings_pack.int_types.unchoke_slots_limit.swigValue(),
            s.maxUploads.toInt(),
        )
        pack.setBoolean(
            org.libtorrent4j.swig.settings_pack.bool_types.enable_dht.swigValue(),
            s.dhtEnabled,
        )
        // libtorrent4j's SessionManager.start() defaults
        // max_metadata_size to 2 MiB. Multi-thousand-file torrents
        // (e.g. archive.org collections) have .torrent blobs larger
        // than that, and peers offering metadata above the limit are
        // silently rejected — leaving the session stuck in
        // downloading_metadata forever even with hundreds of peers
        // connected. Bump it to 32 MiB to cover any reasonable
        // .torrent we'd ever download.
        pack.setInteger(
            org.libtorrent4j.swig.settings_pack.int_types.max_metadata_size.swigValue(),
            32 * 1024 * 1024,
        )
        // Disable UPnP / NAT-PMP / LSD on Android. They all bind to
        // multicast sockets, which requires CHANGE_WIFI_MULTICAST_STATE
        // and a held WifiManager.MulticastLock. Without those the
        // kernel returns EACCES on bind() and libtorrent posts a
        // session_error_alert that aborts listen setup — leaving the
        // session running but unable to talk to peers or trackers.
        // We don't need these services on mobile: carrier NAT makes
        // port mapping useless, and LSD only matters on LANs we're
        // unlikely to be hosting on.
        pack.setBoolean(
            org.libtorrent4j.swig.settings_pack.bool_types.enable_upnp.swigValue(),
            false,
        )
        pack.setBoolean(
            org.libtorrent4j.swig.settings_pack.bool_types.enable_natpmp.swigValue(),
            false,
        )
        pack.setBoolean(
            org.libtorrent4j.swig.settings_pack.bool_types.enable_lsd.swigValue(),
            false,
        )
        // Hit every tracker in every tier on each announce. Without
        // this, libtorrent picks one tracker per tier and stops on the
        // first one that replies — which on archive.org torrents
        // usually means we get random public-tracker peers that don't
        // actually hold the data, and we never reach archive.org's own
        // seed servers via udp://bt1.archive.org:6969.
        pack.setBoolean(
            org.libtorrent4j.swig.settings_pack.bool_types.announce_to_all_trackers.swigValue(),
            true,
        )
        pack.setBoolean(
            org.libtorrent4j.swig.settings_pack.bool_types.announce_to_all_tiers.swigValue(),
            true,
        )
        // Alert categories libtorrent will surface to AlertListener.
        // Default is error_notification only — without enabling tracker
        // and dht categories, peer discovery never emits events and
        // (more importantly) the related internal loops don't run.
        val alertMask = (
            0x1 or    // error
            0x2 or    // peer
            0x10 or   // tracker
            0x40 or   // status
            0x400     // dht
        )
        pack.setInteger(
            org.libtorrent4j.swig.settings_pack.int_types.alert_mask.swigValue(),
            alertMask,
        )
        // Default DHT bootstrap nodes — match libtorrent's recommended
        // list. Without these the routing table never seeds and DHT
        // can't find peers for the first torrent of a session.
        pack.setString(
            org.libtorrent4j.swig.settings_pack.string_types.dht_bootstrap_nodes.swigValue(),
            "router.bittorrent.com:6881," +
                "router.utorrent.com:6881," +
                "dht.transmissionbt.com:6881," +
                "dht.libtorrent.org:25401",
        )
        // IPv4-only on Android: many carrier/Wi-Fi stacks fail IPv6 bind,
        // and a failed `[::]` listen can take the whole listen socket
        // down with it — leaving the session alive but unable to
        // announce or connect to peers. Port 0 lets the OS pick a free
        // port, which avoids the "6881 already used / firewalled"
        // class of failures on mobile.
        pack.setString(
            org.libtorrent4j.swig.settings_pack.string_types.listen_interfaces.swigValue(),
            "0.0.0.0:0",
        )
        return pack
    }

    private fun stateToString(state: TorrentStatus.State?): String = when (state) {
        TorrentStatus.State.CHECKING_FILES -> "checking_files"
        TorrentStatus.State.DOWNLOADING_METADATA -> "downloading_metadata"
        TorrentStatus.State.DOWNLOADING -> "downloading"
        TorrentStatus.State.FINISHED -> "finished"
        TorrentStatus.State.SEEDING -> "seeding"
        TorrentStatus.State.CHECKING_RESUME_DATA -> "checking_resume"
        else -> "unknown"
    }

    private fun priorityToInt(p: Priority): Int = when (p) {
        Priority.IGNORE -> 0
        Priority.LOW -> 1
        Priority.TWO -> 2
        Priority.THREE -> 3
        Priority.DEFAULT -> 4
        Priority.FIVE -> 5
        Priority.SIX -> 6
        Priority.TOP_PRIORITY -> 7
        else -> 4
    }

    fun shutdown() {
        pollFuture?.cancel(false)
        pollingExecutor.shutdownNow()
        session?.stop()
        session = null
    }
}
