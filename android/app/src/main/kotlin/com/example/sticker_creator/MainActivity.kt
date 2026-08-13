package com.example.sticker_creator

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "sticker_creator/whatsapp"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isWhatsAppInstalled" -> result.success(isWhatsAppInstalled())
                "addPack" -> {
                    addPack(call.arguments as Map<*, *>)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun isWhatsAppInstalled(): Boolean {
        return try {
            packageManager.getPackageInfo("com.whatsapp", PackageManager.GET_ACTIVITIES)
            true
        } catch (e: PackageManager.NameNotFoundException) {
            false
        }
    }

    private fun addPack(args: Map<*, *>) {
        val packId = args["id"] as String
        val stickers = args["stickers"] as List<*>

        val packsFile = File(filesDir, "whatsapp_export/packs.json")
        packsFile.parentFile?.mkdirs()
        val allPacks = if (packsFile.exists()) JSONObject(packsFile.readText()) else JSONObject()

        val packJson = JSONObject().apply {
            put("name", args["name"])
            put("publisher", args["publisher"])
            put("trayIconPath", args["trayIconPath"])
            put("trayIconFileName", "tray_$packId.png")
            put("isAnimated", stickers.any { (it as Map<*, *>)["type"] == "animated" })
            put("stickers", JSONArray(stickers.mapIndexed { i, s ->
                val sticker = s as Map<*, *>
                JSONObject().apply {
                    put("fileName", "sticker_${packId}_$i.webp")
                    put("filePath", sticker["filePath"])
                }
            }))
        }
        allPacks.put(packId, packJson)
        packsFile.writeText(allPacks.toString())

        val intent = Intent().apply {
            action = "com.whatsapp.intent.action.ENQUEUE_STICKER_PACK"
            putExtra("sticker_pack_id", packId)
            putExtra("sticker_pack_authority", "$packageName.stickercontentprovider")
            putExtra("sticker_pack_name", args["name"] as String)
        }
        try {
            startActivityForResult(intent, 200)
        } catch (e: ActivityNotFoundException) {
            // Dart side already checks isWhatsAppInstalled() before calling addPack,
            // but handle the race (WhatsApp uninstalled mid-flow) without crashing.
        }
    }
}
