package com.example.quorum_app

import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var autoEnter = false
    private var ratio = Rational(9, 16)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "quorum/pip")
        channel = ch
        ch.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(isPipSupported())
                "setAutoEnter" -> {
                    autoEnter = call.argument<Boolean>("enabled") ?: false
                    ratio = ratioFrom(call.argument<Int>("width"), call.argument<Int>("height"))
                    applyParams()
                    result.success(true)
                }
                "enter" -> {
                    ratio = ratioFrom(call.argument<Int>("width"), call.argument<Int>("height"))
                    result.success(enterPip())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun ratioFrom(w: Int?, h: Int?): Rational {
        val width = if (w != null && w > 0) w else 9
        val height = if (h != null && h > 0) h else 16
        val value = width.toDouble() / height.toDouble()
        return if (value < 0.42 || value > 2.38) Rational(9, 16) else Rational(width, height)
    }

    private fun isPipSupported(): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    private fun buildParams(): PictureInPictureParams {
        val builder = PictureInPictureParams.Builder().setAspectRatio(ratio)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoEnter)
            builder.setSeamlessResizeEnabled(false)
        }
        return builder.build()
    }

    private fun applyParams() {
        if (isPipSupported()) {
            try {
                setPictureInPictureParams(buildParams())
            } catch (_: Exception) {
            }
        }
    }

    private fun enterPip(): Boolean {
        if (!isPipSupported()) return false
        return try {
            enterPictureInPictureMode(buildParams())
        } catch (_: Exception) {
            false
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (autoEnter && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            enterPip()
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("onPipChanged", isInPictureInPictureMode)
    }
}