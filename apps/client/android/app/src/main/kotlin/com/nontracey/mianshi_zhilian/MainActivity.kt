package com.nontracey.mianshi_zhilian

import android.os.Build
import android.os.Process
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "mianshi_zhilian/runtime"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAndroidRuntimeInfo" -> result.success(
                    mapOf(
                        "is64Bit" to isProcess64Bit(),
                        "supportedAbis" to Build.SUPPORTED_ABIS.toList(),
                        "supported64BitAbis" to Build.SUPPORTED_64_BIT_ABIS.toList(),
                        "supported32BitAbis" to Build.SUPPORTED_32_BIT_ABIS.toList(),
                    )
                )
                else -> result.notImplemented()
            }
        }
    }

    private fun isProcess64Bit(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            return Process.is64Bit()
        }
        val primaryAbi = Build.SUPPORTED_ABIS.firstOrNull() ?: return false
        return Build.SUPPORTED_64_BIT_ABIS.contains(primaryAbi)
    }
}
