package com.nebras.nebras_dashboard

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

/// «مشاركة إلى نبراس» — استقبال ACTION_SEND/SEND_MULTIPLE (ملفّ أو نصّ)
/// وتمريره إلى Flutter عبر MethodChannel بسيط (بديل أصلي عن حزمة
/// receive_sharing_intent غير المتوافقة مع Gradle الحديث).
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingShare: Map<String, String?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "nebras/share")
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                // Flutter يسأل عند الإقلاع: هل فُتحتُ عبر مشاركة؟
                "getInitialShare" -> {
                    result.success(pendingShare)
                    pendingShare = null
                }
                else -> result.notImplemented()
            }
        }
        handleShareIntent(intent, deliverNow = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // التطبيق مفتوح بالفعل — نسلّم المشاركة فوراً.
        handleShareIntent(intent, deliverNow = true)
    }

    private fun handleShareIntent(intent: Intent?, deliverNow: Boolean) {
        if (intent == null) return
        val action = intent.action
        if (action != Intent.ACTION_SEND && action != Intent.ACTION_SEND_MULTIPLE) return

        val text = intent.getStringExtra(Intent.EXTRA_TEXT)
        @Suppress("DEPRECATION")
        val uri: Uri? = when (action) {
            Intent.ACTION_SEND -> intent.getParcelableExtra(Intent.EXTRA_STREAM)
            Intent.ACTION_SEND_MULTIPLE ->
                intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.firstOrNull()
            else -> null
        }
        val path = uri?.let { copyToCache(it) }
        if (path == null && text.isNullOrBlank()) return

        val payload = mapOf("path" to path, "text" to text)
        if (deliverNow && channel != null) {
            channel?.invokeMethod("onShare", payload)
        } else {
            pendingShare = payload
        }
    }

    /// نسخ content:// إلى ملفّ مؤقّت يستطيع Flutter قراءته مباشرة.
    private fun copyToCache(uri: Uri): String? {
        return try {
            val name = displayName(uri) ?: "shared_${System.currentTimeMillis()}"
            val safe = name.replace(Regex("[\\\\/:*?\"<>|]"), "_")
            val outFile = File(cacheDir, "share_${System.currentTimeMillis()}_$safe")
            contentResolver.openInputStream(uri)?.use { input ->
                FileOutputStream(outFile).use { output -> input.copyTo(output) }
            } ?: return null
            outFile.absolutePath
        } catch (_: Exception) {
            null
        }
    }

    private fun displayName(uri: Uri): String? {
        return try {
            contentResolver.query(uri, null, null, null, null)?.use { c ->
                val idx = c.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (idx >= 0 && c.moveToFirst()) c.getString(idx) else null
            }
        } catch (_: Exception) {
            null
        }
    }
}
