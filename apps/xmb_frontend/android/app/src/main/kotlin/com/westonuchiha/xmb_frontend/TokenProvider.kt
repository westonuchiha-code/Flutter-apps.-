package com.westonuchiha.xmb_frontend

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri

/// One sign-in for both apps: hands the menu's Cross-Save GitHub token to
/// the Pokéville app. Only apps signed with the same key may ask (the
/// signature permission in AndroidManifest.xml); the token lives in this
/// app's private preferences, never in shared storage.
class TokenProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?
    ): Cursor {
        val c = MatrixCursor(arrayOf(COLUMN))
        c.addRow(arrayOf(read(context ?: return c)))
        return c
    }

    override fun getType(uri: Uri): String = "vnd.android.cursor.item/vnd.westonuchiha.token"

    // Read-only: the menu writes the token through its MethodChannel.
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?
    ): Int = 0

    companion object {
        private const val PREFS = "cross_save"
        private const val KEY = "token"
        const val COLUMN = "token"

        fun read(context: Context): String =
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, "") ?: ""

        fun write(context: Context, token: String) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit().putString(KEY, token).commit()
        }
    }
}
