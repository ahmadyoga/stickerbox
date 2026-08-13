package com.example.sticker_creator

import android.content.ContentProvider
import android.content.ContentValues
import android.content.res.AssetFileDescriptor
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import org.json.JSONObject
import java.io.File

class StickerContentProvider : ContentProvider() {
    private val authority get() = "${context!!.packageName}.stickercontentprovider"

    private fun packsFile() = File(context!!.filesDir, "whatsapp_export/packs.json")

    private fun readPacks(): JSONObject =
        if (packsFile().exists()) JSONObject(packsFile().readText()) else JSONObject()

    override fun onCreate(): Boolean = true

    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
                        selectionArgs: Array<out String>?, sortOrder: String?): Cursor? {
        val segments = uri.pathSegments
        return when (segments.getOrNull(0)) {
            "metadata" -> queryMetadata()
            "stickers" -> queryStickers(segments.getOrNull(1))
            else -> null
        }
    }

    private fun queryMetadata(): Cursor {
        val cursor = MatrixCursor(arrayOf(
            "sticker_pack_identifier", "sticker_pack_name", "sticker_pack_publisher",
            "sticker_pack_icon", "android_play_store_link", "ios_app_download_link",
            "publisher_email", "publisher_website", "privacy_policy_website",
            "license_agreement_website", "image_data_version", "avoid_cache",
            "animated_sticker_pack",
        ))
        val packs = readPacks()
        for (id in packs.keys()) {
            val pack = packs.getJSONObject(id)
            cursor.addRow(arrayOf(
                id, pack.getString("name"), pack.getString("publisher"),
                pack.optString("trayIconFileName"), "", "", "", "", "", "",
                "1", 0, if (pack.getBoolean("isAnimated")) 1 else 0,
            ))
        }
        return cursor
    }

    private fun queryStickers(packId: String?): Cursor {
        val cursor = MatrixCursor(arrayOf("sticker_file_name", "sticker_emoji"))
        if (packId == null) return cursor
        val pack = readPacks().optJSONObject(packId) ?: return cursor
        val stickers = pack.getJSONArray("stickers")
        for (i in 0 until stickers.length()) {
            cursor.addRow(arrayOf(stickers.getJSONObject(i).getString("fileName"), ""))
        }
        return cursor
    }

    override fun openAssetFile(uri: Uri, mode: String): AssetFileDescriptor? {
        val segments = uri.pathSegments
        if (segments.getOrNull(0) != "stickers_asset") return null
        val packId = segments.getOrNull(1) ?: return null
        val fileName = segments.getOrNull(2) ?: return null
        val pack = readPacks().optJSONObject(packId) ?: return null
        val trayIconFileName = pack.optString("trayIconFileName")
        val filePath = if (trayIconFileName.isNotEmpty() && fileName == trayIconFileName) {
            pack.optString("trayIconPath").ifEmpty { return null }
        } else {
            val stickers = pack.getJSONArray("stickers")
            (0 until stickers.length())
                .map { stickers.getJSONObject(it) }
                .firstOrNull { it.getString("fileName") == fileName }
                ?.getString("filePath") ?: return null
        }
        val pfd = ParcelFileDescriptor.open(File(filePath), ParcelFileDescriptor.MODE_READ_ONLY)
        return AssetFileDescriptor(pfd, 0, AssetFileDescriptor.UNKNOWN_LENGTH)
    }

    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = 0
}
