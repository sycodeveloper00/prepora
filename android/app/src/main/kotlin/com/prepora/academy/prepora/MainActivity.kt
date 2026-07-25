package com.prepora.academy.prepora

import android.content.Intent
import android.webkit.URLUtil
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.prepora.academy.prepora/pdf_intent"
    private var methodChannel: MethodChannel? = null
    private var initialPdfUri: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPdfUri" -> {
                    val uri = initialPdfUri
                    initialPdfUri = null
                    result.success(uri)
                }
                "copyContentUriToTemp" -> {
                    try {
                        val uriString = call.arguments as String
                        val uri = android.net.Uri.parse(uriString)
                        val fileName = URLUtil.guessFileName(uriString, null, null)
                        val tempFile = File(cacheDir, "pdf_cache/$fileName")
                        tempFile.parentFile?.mkdirs()
                        contentResolver.openInputStream(uri)?.use { input ->
                            tempFile.outputStream().use { output ->
                                input.copyTo(output)
                            }
                        }
                        result.success(tempFile.absolutePath)
                    } catch (e: Exception) {
                        result.error("COPY_FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent) {
        if (intent.action == Intent.ACTION_VIEW) {
            val uri = intent.data
            if (uri != null) {
                val uriString = uri.toString()
                if (uriString.endsWith(".pdf", ignoreCase = true)) {
                    if (methodChannel != null) {
                        methodChannel!!.invokeMethod("openPdf", uriString)
                    } else {
                        initialPdfUri = uriString
                    }
                }
            }
        }
    }
}
