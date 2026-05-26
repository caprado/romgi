package com.caprado.romgi.seven_zip

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import org.apache.commons.compress.archivers.sevenz.SevenZArchiveEntry
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import org.apache.commons.compress.archivers.zip.ZipArchiveInputStream
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

private const val TAG = "SevenZipService"

class SevenZipServiceImpl(
    binaryMessenger: BinaryMessenger,
) : SevenZipHostApi {

    private val events = SevenZipEvents(binaryMessenger)
    private val mainHandler = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor { r ->
        Thread(r, "7z-extract").apply { isDaemon = true }
    }
    private val cancelledPaths: MutableSet<String> = ConcurrentHashMap.newKeySet()

    override fun extract(
        archivePath: String,
        outputDir: String,
        callback: (Result<String>) -> Unit,
    ) {
        val archiveFile = File(archivePath)
        if (!archiveFile.exists()) {
            callback(Result.failure(Exception("Archive not found: $archivePath")))
            return
        }

        cancelledPaths.remove(archivePath)

        executor.execute {
            try {
                val result = doExtract(archiveFile, File(outputDir))
                mainHandler.post { callback(Result.success(result)) }
            } catch (e: Exception) {
                Log.e(TAG, "extraction failed: $archivePath", e)
                mainHandler.post { callback(Result.failure(e)) }
            }
        }
    }

    override fun cancel(archivePath: String) {
        cancelledPaths.add(archivePath)
    }

    private fun doExtract(archiveFile: File, outputDir: File): String {
        val name = archiveFile.name.lowercase()
        return when {
            name.endsWith(".zip") -> doExtractZip(archiveFile, outputDir)
            else -> doExtract7z(archiveFile, outputDir)
        }
    }

    private fun doExtractZip(archiveFile: File, outputDir: File): String {
        outputDir.mkdirs()
        val archivePath = archiveFile.absolutePath

        // First pass: compute total uncompressed size for progress.
        var totalBytes: Long = 0
        ZipArchiveInputStream(BufferedInputStream(FileInputStream(archiveFile))).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                if (!entry.isDirectory && entry.size > 0) {
                    totalBytes += entry.size
                }
                entry = zis.nextEntry
            }
        }

        Log.i(TAG, "extracting zip $archivePath totalBytes=$totalBytes")

        // Second pass: extract.
        var bytesExtracted: Long = 0
        var lastProgressTime = 0L
        val extractedFiles = mutableListOf<String>()

        ZipArchiveInputStream(BufferedInputStream(FileInputStream(archiveFile))).use { zis ->
            val buffer = ByteArray(64 * 1024)
            var entry = zis.nextEntry

            while (entry != null) {
                if (cancelledPaths.contains(archivePath)) {
                    throw Exception("Extraction cancelled")
                }

                val outFile = File(outputDir, entry.name)

                // Guard against zip-slip.
                if (!outFile.canonicalPath.startsWith(outputDir.canonicalPath + File.separator)) {
                    entry = zis.nextEntry
                    continue
                }

                if (entry.isDirectory) {
                    outFile.mkdirs()
                } else {
                    outFile.parentFile?.mkdirs()
                    FileOutputStream(outFile).use { fos ->
                        var len: Int
                        while (zis.read(buffer).also { len = it } > 0) {
                            if (cancelledPaths.contains(archivePath)) {
                                throw Exception("Extraction cancelled")
                            }
                            fos.write(buffer, 0, len)
                            bytesExtracted += len

                            val now = System.currentTimeMillis()
                            if (now - lastProgressTime >= 200) {
                                lastProgressTime = now
                                val progress = ExtractionProgress(
                                    archivePath = archivePath,
                                    bytesExtracted = bytesExtracted,
                                    totalBytes = totalBytes,
                                )
                                mainHandler.post {
                                    events.onProgress(progress) { }
                                }
                            }
                        }
                    }
                    extractedFiles.add(outFile.absolutePath)
                }
                entry = zis.nextEntry
            }
        }

        mainHandler.post {
            events.onProgress(
                ExtractionProgress(
                    archivePath = archivePath,
                    bytesExtracted = totalBytes,
                    totalBytes = totalBytes,
                )
            ) { }
        }

        cancelledPaths.remove(archivePath)

        // Prefer the files we just wrote (handles re-extraction where
        // files already existed before extraction started).
        val result = when {
            extractedFiles.size == 1 -> extractedFiles.first()
            extractedFiles.isNotEmpty() -> {
                extractedFiles.maxByOrNull { File(it).length() } ?: outputDir.absolutePath
            }
            else -> outputDir.absolutePath
        }

        Log.i(TAG, "zip extraction complete: $result (${extractedFiles.size} files)")
        return result
    }

    private fun doExtract7z(archiveFile: File, outputDir: File): String {
        outputDir.mkdirs()
        val archivePath = archiveFile.absolutePath

        // First pass: compute total uncompressed size for progress.
        var totalBytes: Long = 0
        SevenZFile.builder().setFile(archiveFile).get().use { szf ->
            var entry: SevenZArchiveEntry? = szf.nextEntry
            while (entry != null) {
                if (!entry.isDirectory) {
                    totalBytes += entry.size
                }
                entry = szf.nextEntry
            }
        }

        Log.i(TAG, "extracting $archivePath totalBytes=$totalBytes")

        // Second pass: extract.
        var bytesExtracted: Long = 0
        var lastProgressTime = 0L
        val extractedFiles = mutableListOf<String>()

        SevenZFile.builder().setFile(archiveFile).get().use { szf ->
            val buffer = ByteArray(64 * 1024)
            var entry: SevenZArchiveEntry? = szf.nextEntry

            while (entry != null) {
                if (cancelledPaths.contains(archivePath)) {
                    throw Exception("Extraction cancelled")
                }

                val outFile = File(outputDir, entry.name)

                // Guard against zip-slip.
                if (!outFile.canonicalPath.startsWith(outputDir.canonicalPath + File.separator)) {
                    entry = szf.nextEntry
                    continue
                }

                if (entry.isDirectory) {
                    outFile.mkdirs()
                } else {
                    outFile.parentFile?.mkdirs()
                    FileOutputStream(outFile).use { fos ->
                        var len: Int
                        while (szf.read(buffer).also { len = it } > 0) {
                            if (cancelledPaths.contains(archivePath)) {
                                throw Exception("Extraction cancelled")
                            }
                            fos.write(buffer, 0, len)
                            bytesExtracted += len

                            // Throttle progress updates to every 200ms.
                            val now = System.currentTimeMillis()
                            if (now - lastProgressTime >= 200) {
                                lastProgressTime = now
                                val progress = ExtractionProgress(
                                    archivePath = archivePath,
                                    bytesExtracted = bytesExtracted,
                                    totalBytes = totalBytes,
                                )
                                mainHandler.post {
                                    events.onProgress(progress) { }
                                }
                            }
                        }
                    }
                    extractedFiles.add(outFile.absolutePath)
                }
                entry = szf.nextEntry
            }
        }

        // Send final 100% progress.
        mainHandler.post {
            events.onProgress(
                ExtractionProgress(
                    archivePath = archivePath,
                    bytesExtracted = totalBytes,
                    totalBytes = totalBytes,
                )
            ) { }
        }

        cancelledPaths.remove(archivePath)

        // Prefer the files we just wrote (handles re-extraction where
        // files already existed before extraction started).
        val result = when {
            extractedFiles.size == 1 -> extractedFiles.first()
            extractedFiles.isNotEmpty() -> {
                extractedFiles.maxByOrNull { File(it).length() } ?: outputDir.absolutePath
            }
            else -> outputDir.absolutePath
        }

        Log.i(TAG, "extraction complete: $result (${extractedFiles.size} files)")
        return result
    }
}
