package com.example.saveit

import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.googlemobileads.GoogleMobileAdsPlugin

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        GoogleMobileAdsPlugin.registerNativeAdFactory(
            flutterEngine,
            "pinterestPin",
            PinterestPinNativeAdFactory(context),
        )
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "eu.savein.app/native_links",
        ).setMethodCallHandler { call, result ->
            if (call.method != "openInPackage") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val url = call.argument<String>("url").orEmpty()
            val packageName = call.argument<String>("package").orEmpty()
            if (url.isEmpty() || packageName.isEmpty()) {
                result.success(false)
                return@setMethodCallHandler
            }
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                setPackage(packageName)
            }
            try {
                startActivity(intent)
                result.success(true)
            } catch (_: ActivityNotFoundException) {
                result.success(false)
            } catch (_: Exception) {
                result.success(false)
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        GoogleMobileAdsPlugin.unregisterNativeAdFactory(flutterEngine, "pinterestPin")
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
