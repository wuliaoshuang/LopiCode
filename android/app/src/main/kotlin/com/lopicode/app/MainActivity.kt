package com.lopicode.app

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * 除了承载 Flutter 界面，还提供一个很小的密钥存储通道 `lopicode/secrets`：
 * 值用 Android Keystore 里的 AES-256-GCM 密钥加密后再放进 SharedPreferences，
 * 密钥本身不出 Keystore。API Key、GitHub Token、SSH 密码都存这里。
 */
class MainActivity : FlutterActivity() {
    private val keyAlias = "lopicode_secrets_v1"
    private val prefsName = "lopicode_secrets"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lopicode/secrets")
            .setMethodCallHandler { call, result ->
                try {
                    val key = call.argument<String>("key")
                    if (key == null) {
                        result.error("bad_args", "missing key", null)
                        return@setMethodCallHandler
                    }
                    val prefs = getSharedPreferences(prefsName, Context.MODE_PRIVATE)
                    when (call.method) {
                        "read" -> {
                            val stored = prefs.getString(key, null)
                            result.success(if (stored == null) null else decrypt(stored))
                        }
                        "write" -> {
                            val value = call.argument<String>("value") ?: ""
                            prefs.edit().putString(key, encrypt(value)).apply()
                            result.success(null)
                        }
                        "delete" -> {
                            prefs.edit().remove(key).apply()
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    // 只回报异常类型，不带任何明文。
                    result.error("keystore_error", e.javaClass.simpleName, null)
                }
            }
    }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(keyAlias, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                keyAlias,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }

    private fun encrypt(plain: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val data = cipher.doFinal(plain.toByteArray(Charsets.UTF_8))
        return Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" + Base64.encodeToString(data, Base64.NO_WRAP)
    }

    private fun decrypt(stored: String): String? {
        val parts = stored.split(":")
        if (parts.size != 2) return null
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey(),
            GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP))
        )
        return String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8)
    }
}
