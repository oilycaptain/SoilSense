package com.soilsense.app

import android.content.ContentValues
import android.content.Context
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val wifiChannelName = "soilsense/wifi_multicast"
    private val downloadChannelName = "soilsense/file_download"
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            wifiChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "acquireMulticastLock" -> {
                    try {
                        val wifiManager = applicationContext
                            .getSystemService(Context.WIFI_SERVICE) as WifiManager
                        if (multicastLock == null) {
                            multicastLock = wifiManager.createMulticastLock("SoilSenseSmartConfig").apply {
                                setReferenceCounted(false)
                            }
                        }
                        if (multicastLock?.isHeld != true) multicastLock?.acquire()
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("MULTICAST_LOCK", error.message, null)
                    }
                }
                "releaseMulticastLock" -> {
                    try {
                        if (multicastLock?.isHeld == true) multicastLock?.release()
                        result.success(null)
                    } catch (error: Exception) {
                        result.error("MULTICAST_UNLOCK", error.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            downloadChannelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "savePdfToDownloads" -> {
                    try {
                        val bytes = call.argument<ByteArray>("bytes")
                        val requestedName = call.argument<String>("fileName")
                        if (bytes == null || bytes.isEmpty()) {
                            result.error("EMPTY_FILE", "The generated PDF is empty.", null)
                            return@setMethodCallHandler
                        }
                        val fileName = sanitizePdfName(requestedName)
                        val savedLocation = savePdfToDownloads(bytes, fileName)
                        result.success(savedLocation)
                    } catch (error: Exception) {
                        result.error("DOWNLOAD_FAILED", error.message ?: "Could not save PDF.", null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun sanitizePdfName(value: String?): String {
        val raw = value?.trim().orEmpty().ifEmpty { "soilsense_report.pdf" }
        val cleaned = raw.replace(Regex("[^A-Za-z0-9._-]"), "_")
        return if (cleaned.lowercase().endsWith(".pdf")) cleaned else "$cleaned.pdf"
    }

    private fun savePdfToDownloads(bytes: ByteArray, fileName: String): String {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val resolver = applicationContext.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/pdf")
                put(
                    MediaStore.MediaColumns.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + File.separator + "SoilSense"
                )
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: throw IllegalStateException("Android could not create the download file.")
            try {
                resolver.openOutputStream(uri, "w")?.use { stream ->
                    stream.write(bytes)
                    stream.flush()
                } ?: throw IllegalStateException("Android could not open the download file.")
                val completed = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(uri, completed, null, null)
                "Downloads/SoilSense/$fileName"
            } catch (error: Exception) {
                resolver.delete(uri, null, null)
                throw error
            }
        } else {
            val downloads = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
            val folder = File(downloads, "SoilSense")
            if (!folder.exists() && !folder.mkdirs()) {
                throw IllegalStateException("Could not create the SoilSense Downloads folder.")
            }
            val file = File(folder, fileName)
            FileOutputStream(file).use { stream ->
                stream.write(bytes)
                stream.flush()
            }
            file.absolutePath
        }
    }

    override fun onDestroy() {
        if (multicastLock?.isHeld == true) multicastLock?.release()
        multicastLock = null
        super.onDestroy()
    }
}
