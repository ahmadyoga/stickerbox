package com.stickerbox

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.BitmapFactory
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "stickerbox/whatsapp"
    private val TAG = "StickerCreator"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isWhatsAppInstalled" -> result.success(isWhatsAppInstalled())
                "addPack" -> {
                    try {
                        addPack(call.arguments as Map<*, *>)
                        result.success(null)
                    } catch (e: Exception) {
                        Log.e(TAG, "Error adding pack", e)
                        result.error("ADD_PACK_ERROR", e.message, null)
                    }
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

    private fun validateStickerImage(filePath: String, isTrayIcon: Boolean = false): String? {
        val file = File(filePath)
        
        if (!file.exists()) {
            return "File does not exist: $filePath"
        }
        
        val fileSize = file.length()
        val maxSize = if (isTrayIcon) 50 * 1024 else 100 * 1024
        
        if (fileSize > maxSize) {
            return "File too large: ${fileSize / 1024}KB (max ${maxSize / 1024}KB)"
        }
        
        val options = BitmapFactory.Options().apply {
            inJustDecodeBounds = true
        }
        BitmapFactory.decodeFile(filePath, options)
        
        val expectedSize = if (isTrayIcon) 96 else 512
        if (options.outWidth != expectedSize || options.outHeight != expectedSize) {
            return "Invalid dimensions: ${options.outWidth}x${options.outHeight} (expected ${expectedSize}x${expectedSize})"
        }
        
        return null
    }

    private fun addPack(args: Map<*, *>) {
        val packId = args["id"] as String
        val packName = args["name"] as String
        val publisher = args["publisher"] as String
        val trayIconPath = args["trayIconPath"] as? String
        val stickers = args["stickers"] as List<*>

        Log.d(TAG, "Adding pack: id=$packId, name=$packName, stickers=${stickers.size}")
        
        // Validate minimum requirements
        if (stickers.size < 3) {
            Log.e(TAG, "Pack must have at least 3 stickers")
            throw IllegalArgumentException("Pack must have at least 3 stickers")
        }
        
        if (stickers.size > 30) {
            Log.e(TAG, "Pack cannot have more than 30 stickers")
            throw IllegalArgumentException("Pack cannot have more than 30 stickers")
        }
        
        if (trayIconPath == null || trayIconPath.isEmpty()) {
            Log.e(TAG, "Tray icon path is required")
            throw IllegalArgumentException("Tray icon path is required")
        }
        
        // Validate tray icon
        val trayError = validateStickerImage(trayIconPath, isTrayIcon = true)
        if (trayError != null) {
            Log.e(TAG, "Tray icon validation failed: $trayError")
            throw IllegalArgumentException("Tray icon: $trayError")
        }
        Log.d(TAG, "Tray icon validated successfully")
        
        // Validate each sticker
        stickers.forEachIndexed { index, s ->
            val sticker = s as Map<*, *>
            val stickerPath = sticker["filePath"] as String
            val stickerError = validateStickerImage(stickerPath, isTrayIcon = false)
            if (stickerError != null) {
                Log.e(TAG, "Sticker $index validation failed: $stickerError")
                throw IllegalArgumentException("Sticker $index: $stickerError")
            }
        }
        Log.d(TAG, "All ${stickers.size} stickers validated successfully")

        val packsFile = File(filesDir, "whatsapp_export/packs.json")
        packsFile.parentFile?.mkdirs()
        val allPacks = if (packsFile.exists()) JSONObject(packsFile.readText()) else JSONObject()

        // WhatsApp caches a pack's tray icon/stickers by (sticker_pack_identifier,
        // image_data_version) and only re-fetches when that version changes — without
        // this bump, editing an already-added pack (rename, new tray icon, add/remove
        // stickers) is invisible to WhatsApp until the user removes and re-adds it.
        val previousVersion = allPacks.optJSONObject(packId)?.optString("imageDataVersion")?.toIntOrNull() ?: 0

        val packJson = JSONObject().apply {
            put("name", packName)
            put("publisher", publisher)
            put("trayIconPath", trayIconPath)
            put("trayIconFileName", "tray_$packId.png")
            put("imageDataVersion", (previousVersion + 1).toString())
            put("isAnimated", stickers.any { (it as Map<*, *>)["type"] == "animated" })
            put("stickers", JSONArray(stickers.map { s ->
                val sticker = s as Map<*, *>
                val stickerId = sticker["id"] as String
                val stickerPath = sticker["filePath"] as String

                // Keyed by the sticker's own stable id (not list position) so a
                // reordered/edited pack can't collide with a stale cached URI that
                // used to point at a different sticker's bytes.
                JSONObject().apply {
                    put("fileName", "sticker_${packId}_$stickerId.webp")
                    put("filePath", stickerPath)
                }
            }))
        }
        allPacks.put(packId, packJson)
        packsFile.writeText(allPacks.toString())
        
        Log.d(TAG, "Pack data saved to: ${packsFile.absolutePath}")

        val intent = Intent().apply {
            action = "com.whatsapp.intent.action.ENABLE_STICKER_PACK"
            setPackage("com.whatsapp")
            putExtra("sticker_pack_id", packId)
            putExtra("sticker_pack_authority", "$packageName.stickercontentprovider")
            putExtra("sticker_pack_name", packName)
        }
        
        Log.d(TAG, "Launching WhatsApp with authority: $packageName.stickercontentprovider")
        
        try {
            startActivityForResult(intent, 200)
        } catch (e: ActivityNotFoundException) {
            Log.e(TAG, "WhatsApp not found", e)
        }
    }
}
