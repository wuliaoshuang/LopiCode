package com.lopicode.app

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.ext.SdkExtensions
import android.provider.OpenableColumns
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executors

/**
 * 选一张图当背景（Dart 那头是 lib/backdrop/backdrop_picker.dart）。
 *
 * 不申请任何权限：优先系统的照片选择器（ACTION_PICK_IMAGES），这台手机没有就退到系统的文件选择器
 * （ACTION_OPEN_DOCUMENT，image/ 开头的类型）。两种都只把用户亲手挑的那一张的临时读取权交给应用。
 *
 * 选中的图不直接过通道：在后台线程里复制到应用缓存目录（cache/backdrop_pick/），只把路径交回 Dart。
 * - JPG / PNG / WebP，而且长边不超过上限：原样流式复制（不整个读进内存）。
 * - 别的格式（GIF 取第一帧、HEIC 等）或者太大的：按 inSampleSize 降采样解码，摆正拍摄方向，缩到上限以内，
 *   有透明的存 PNG、没有的存 JPG（质量 90）。
 * - 原文件超过字节上限：不读，直接回 too_large。
 *
 * 回给 Dart 的只有错误代号（too_large / unsupported / read_failed / no_picker / no_space / busy），人话在 Dart 那头。
 */
class BackdropPicker(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "lopicode/backdrop")
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    /** 正在等系统选择器回来的那一次。同一时间只受理一次。 */
    private var pending: MethodChannel.Result? = null
    private var maxBytes = 20L * 1024 * 1024
    private var maxSide = 2560

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "pickImage" -> {
                    if (pending != null) {
                        result.error("busy", null, null)
                    } else {
                        maxBytes = (call.argument<Number>("maxBytes"))?.toLong() ?: maxBytes
                        maxSide = (call.argument<Number>("maxSide"))?.toInt() ?: maxSide
                        launch(result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pending = null
        worker.shutdown()
    }

    private fun photoPickerAvailable(): Boolean =
        Build.VERSION.SDK_INT >= 33 ||
            (Build.VERSION.SDK_INT >= 30 && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)

    private fun launch(result: MethodChannel.Result) {
        val intents = ArrayList<Intent>()
        if (photoPickerAvailable()) {
            // MediaStore.ACTION_PICK_IMAGES；写成字面量，编译用的 SDK 低一点也不影响
            intents.add(Intent("android.provider.action.PICK_IMAGES").setType("image/*"))
        }
        intents.add(Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/*"))
        for (intent in intents) {
            try {
                pending = result
                activity.startActivityForResult(intent, REQUEST_CODE)
                return
            } catch (e: ActivityNotFoundException) {
                pending = null
            } catch (e: SecurityException) {
                pending = null
            }
        }
        result.error("no_picker", null, null)
    }

    /** MainActivity.onActivityResult 转过来的；返回 true＝是这里的请求，已经处理。 */
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE) return false
        val result = pending ?: return true
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            result.success(mapOf("status" to "cancelled"))
            return true
        }
        worker.execute {
            val outcome = try {
                Outcome(path = copyToCache(uri))
            } catch (e: PickError) {
                Outcome(error = e.code)
            } catch (e: IOException) {
                Outcome(error = if (e.message?.contains("ENOSPC") == true) "no_space" else "read_failed")
            } catch (e: SecurityException) {
                Outcome(error = "read_failed")
            } catch (e: OutOfMemoryError) {
                Outcome(error = "too_large")
            } catch (e: RuntimeException) {
                Outcome(error = "read_failed")
            }
            main.post {
                if (pending === result) {
                    pending = null
                    if (outcome.path != null) {
                        result.success(mapOf("status" to "ok", "path" to outcome.path))
                    } else {
                        result.error(outcome.error ?: "read_failed", null, null)
                    }
                }
            }
        }
        return true
    }

    private class Outcome(val path: String? = null, val error: String? = null)

    private class PickError(val code: String) : Exception(code)

    private fun sizeOf(uri: Uri): Long {
        try {
            activity.contentResolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)?.use { c ->
                val i = c.getColumnIndex(OpenableColumns.SIZE)
                if (i >= 0 && c.moveToFirst() && !c.isNull(i)) return c.getLong(i)
            }
        } catch (e: RuntimeException) {
            // 查不到大小就当不知道，复制时再按字节数拦
        }
        return -1
    }

    private fun copyToCache(uri: Uri): String {
        val resolver = activity.contentResolver
        if (sizeOf(uri) > maxBytes) throw PickError("too_large")

        // 只看尺寸和类型，不解码像素
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        (resolver.openInputStream(uri) ?: throw PickError("read_failed")).use { BitmapFactory.decodeStream(it, null, bounds) }
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) throw PickError("unsupported")
        val mime = bounds.outMimeType ?: ""
        val ext = when (mime) {
            "image/jpeg" -> "jpg"
            "image/png" -> "png"
            "image/webp" -> "webp"
            else -> null
        }

        val dir = File(activity.cacheDir, "backdrop_pick")
        // 上一次留下的缓存副本先清掉
        dir.listFiles()?.forEach { it.delete() }
        if (!dir.mkdirs() && !dir.isDirectory) throw PickError("no_space")
        val stamp = System.currentTimeMillis()

        if (ext != null && maxOf(bounds.outWidth, bounds.outHeight) <= maxSide) {
            // 原样流式复制，边复制边数字节
            val out = File(dir, "pick-$stamp.$ext")
            var total = 0L
            (resolver.openInputStream(uri) ?: throw PickError("read_failed")).use { input ->
                FileOutputStream(out).use { output ->
                    val buf = ByteArray(64 * 1024)
                    while (true) {
                        val n = input.read(buf)
                        if (n < 0) break
                        total += n
                        if (total > maxBytes) {
                            output.close()
                            out.delete()
                            throw PickError("too_large")
                        }
                        output.write(buf, 0, n)
                    }
                }
            }
            if (total == 0L) {
                out.delete()
                throw PickError("read_failed")
            }
            return out.path
        }

        // 太大或别的格式：降采样解码 → 摆正 → 缩到上限 → 重新编码
        var sample = 1
        while (maxOf(bounds.outWidth, bounds.outHeight) / (sample * 2) >= maxSide) sample *= 2
        val opts = BitmapFactory.Options().apply { inSampleSize = sample }
        var bitmap = (resolver.openInputStream(uri) ?: throw PickError("read_failed")).use { BitmapFactory.decodeStream(it, null, opts) }
            ?: throw PickError("unsupported")

        val degrees = try {
            resolver.openInputStream(uri)?.use { stream ->
                when (ExifInterface(stream).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                    ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                    ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                    ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                    else -> 0f
                }
            } ?: 0f
        } catch (e: IOException) {
            0f
        }
        val longSide = maxOf(bitmap.width, bitmap.height)
        val scale = if (longSide > maxSide) maxSide.toFloat() / longSide else 1f
        if (degrees != 0f || scale != 1f) {
            val m = Matrix().apply {
                postScale(scale, scale)
                postRotate(degrees)
            }
            val turned = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, m, true)
            if (turned !== bitmap) bitmap.recycle()
            bitmap = turned
        }
        val alpha = bitmap.hasAlpha()
        val out = File(dir, "pick-$stamp.${if (alpha) "png" else "jpg"}")
        val ok = FileOutputStream(out).use { bitmap.compress(if (alpha) Bitmap.CompressFormat.PNG else Bitmap.CompressFormat.JPEG, 90, it) }
        bitmap.recycle()
        if (!ok) {
            out.delete()
            throw PickError("read_failed")
        }
        return out.path
    }

    companion object {
        const val REQUEST_CODE = 4217
    }
}
