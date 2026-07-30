package com.clockster.geo_probe

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Android side of the geo_probe engine — STUB.
 *
 * The channel contract mirrors iOS (see ios/Runner/AppDelegate.swift).
 * The real implementation should use the platform GeofencingClient
 * (NOT a location foreground service — Google removes geofencing as an
 * approved FGS use case on 26 Aug 2026). See GeofenceBroadcastReceiver
 * and BootReceiver for the prepared skeletons.
 */
class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "geo_probe/engine",
        ).setMethodCallHandler { call, result ->
            // TODO(android): implement with GeofencingClient + FusedLocationProviderClient.
            when (call.method) {
                "requestPermissions" -> result.success("unavailable")
                "getDiagnostics" -> result.success(
                    mapOf(
                        "available" to false,
                        "note" to "Android engine not implemented yet",
                    ),
                )
                "syncRegions", "setConfig", "requestStateForRegions",
                "requestInitialPermissions",
                -> result.success(null)
                "drainNativeEvents" -> result.success(emptyList<Map<String, Any>>())
                "getCurrentLocation" -> result.success(null)
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "geo_probe/events",
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    // TODO(android): keep the sink and push geofence events to Dart.
                }

                override fun onCancel(arguments: Any?) = Unit
            },
        )
    }
}
