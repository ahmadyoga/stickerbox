package com.stickerbox

import android.content.ContentProvider
import android.content.ContentValues
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import org.json.JSONObject
import java.io.File

class StickerContentProvider : ContentProvider() {
    private val TAG = "StickerContentProvider"
    private val authority get() = "${context!!.packageName}.stickercontentprovider"

    private fun packsFile() = File(context!!.filesDir, "whatsapp_export/packs.json")

    private fun readPacks(): JSONObject =
        if (packsFile().exists()) JSONObject(packsFile().readText()) else JSONObject()

    override fun onCreate(): Boolean {
        Log.d(TAG, "ContentProvider created with authority: $authority")
        return true
    }

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
                        selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
        val segments = uri.pathSegments
        Log.d(TAG, "Query called for URI: $uri, segments: $segments")
        
        return when (segments.getOrNull(0)) {
            "metadata" -> {
                val packId = segments.getOrNull(1)
                queryMetadata(packId)
            }
            "stickers" -> queryStickers(segments.getOrNull(1))
            else -> {
                Log.w(TAG, "Unknown query path: ${segments.getOrNull(0)}")
                null
            }
        }
    }

    private fun queryMetadata(requestedPackId: String?): Cursor {
        val cursor = MatrixCursor(arrayOf(
            "sticker_pack_identifier", "sticker_pack_name", "sticker_pack_publisher",
            "sticker_pack_icon", "android_play_store_link", "ios_app_download_link",
            "publisher_email", "publisher_website", "privacy_policy_website",
            "license_agreement_website", "image_data_version", "avoid_cache",
            "animated_sticker_pack",
        ))
        val packs = readPacks()
        Log.d(TAG, "queryMetadata: Found ${packs.length()} packs, requested: $requestedPackId")
        
        // If a specific pack is requested, only return that one
        if (requestedPackId != null) {
            val pack = packs.optJSONObject(requestedPackId)
            if (pack != null) {
                val trayIconFileName = pack.optString("trayIconFileName")
                val isAnimated = pack.optBoolean("isAnimated", false)
                val imageDataVersion = pack.optString("imageDataVersion").ifEmpty { "1" }

                Log.d(TAG, "Pack: $requestedPackId, name=${pack.getString("name")}, trayIcon=$trayIconFileName, animated=$isAnimated, version=$imageDataVersion")

                cursor.addRow(arrayOf(
                    requestedPackId, pack.getString("name"), pack.getString("publisher"),
                    trayIconFileName, "", "", "", "", "", "",
                    imageDataVersion, 0, if (isAnimated) 1 else 0,
                ))
            } else {
                Log.w(TAG, "Requested pack $requestedPackId not found")
            }
        } else {
            // Return all packs if no specific pack requested
            for (id in packs.keys()) {
                val pack = packs.getJSONObject(id)
                val trayIconFileName = pack.optString("trayIconFileName")
                val isAnimated = pack.optBoolean("isAnimated", false)
                val imageDataVersion = pack.optString("imageDataVersion").ifEmpty { "1" }

                Log.d(TAG, "Pack: $id, name=${pack.getString("name")}, trayIcon=$trayIconFileName, animated=$isAnimated, version=$imageDataVersion")

                cursor.addRow(arrayOf(
                    id, pack.getString("name"), pack.getString("publisher"),
                    trayIconFileName, "", "", "", "", "", "",
                    imageDataVersion, 0, if (isAnimated) 1 else 0,
                ))
            }
        }
        return cursor
    }

    private fun queryStickers(packId: String?): Cursor {
        val cursor = MatrixCursor(arrayOf("sticker_file_name", "sticker_emoji"))
        if (packId == null) {
            Log.w(TAG, "queryStickers: packId is null")
            return cursor
        }
        
        val pack = readPacks().optJSONObject(packId)
        if (pack == null) {
            Log.w(TAG, "queryStickers: Pack not found for id=$packId")
            return cursor
        }
        
        val stickers = pack.getJSONArray("stickers")
        Log.d(TAG, "queryStickers: Pack $packId has ${stickers.length()} stickers")
        
        for (i in 0 until stickers.length()) {
            val fileName = stickers.getJSONObject(i).getString("fileName")
            Log.d(TAG, "  Sticker $i: $fileName")
            cursor.addRow(arrayOf(fileName, ""))
        }
        return cursor
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        val segments = uri.pathSegments
        Log.d(TAG, "openAssetFile: URI=$uri, segments=$segments")
        
        if (segments.getOrNull(0) != "stickers_asset") {
            Log.w(TAG, "openAssetFile: Invalid path, expected 'stickers_asset', got '${segments.getOrNull(0)}'")
            return null
        }
        
        val packId = segments.getOrNull(1)
        val fileName = segments.getOrNull(2)
        
        if (packId == null || fileName == null) {
            Log.w(TAG, "openAssetFile: Missing packId or fileName")
            return null
        }
        
        val pack = readPacks().optJSONObject(packId)
        if (pack == null) {
            Log.w(TAG, "openAssetFile: Pack not found for id=$packId")
            return null
        }
        
        val trayIconFileName = pack.optString("trayIconFileName")
        val filePath = if (trayIconFileName.isNotEmpty() && fileName == trayIconFileName) {
            pack.optString("trayIconPath").ifEmpty { 
                Log.e(TAG, "openAssetFile: Tray icon path is empty")
                return null 
            }
        } else {
            val stickers = pack.getJSONArray("stickers")
            val stickerObj = (0 until stickers.length())
                .map { stickers.getJSONObject(it) }
                .firstOrNull { it.getString("fileName") == fileName }
            
            if (stickerObj == null) {
                Log.w(TAG, "openAssetFile: Sticker not found with fileName=$fileName")
                return null
            }
            
            stickerObj.getString("filePath")
        }
        
        val file = File(filePath)
        if (!file.exists()) {
            Log.e(TAG, "openAssetFile: File does not exist: $filePath")
            return null
        }
        
        Log.d(TAG, "openAssetFile: Opening file $filePath (size=${file.length()} bytes)")
        
        val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        return AssetFileDescriptor(pfd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
    }

    override fun getType(uri: Uri): String? {
        val segments = uri.pathSegments
        if (segments.size < 2) return null
        
        val mimeType = when (segments[0]) {
            "stickers_asset" -> {
                val fileName = segments.getOrNull(2) ?: return null
                when {
                    fileName.endsWith(".webp") -> "image/webp"
                    fileName.endsWith(".png") -> "image/png"
                    else -> "image/webp"
                }
            }
            else -> null
        }
        
        Log.d(TAG, "getType: URI=$uri, returning $mimeType")
        return mimeType
    }
    
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
}
