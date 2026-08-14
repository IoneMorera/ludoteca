package com.ludoteca.ludoteca_mobile

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.sqlite.SQLiteDatabase
import android.net.Uri
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileNotFoundException

/**
 * Expone un snapshot consistente de la BBDD local para que Dev pueda clonarla.
 * Solo accesible por apps firmadas con la misma clave.
 */
class LocalDbCloneProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val ctx = context ?: throw FileNotFoundException("Sin contexto")
        val dbFile = ctx.getDatabasePath(DB_NAME)
        if (!dbFile.exists()) {
            throw FileNotFoundException("no_database")
        }
        checkpoint(dbFile)
        return ParcelFileDescriptor.open(dbFile, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    override fun getType(uri: Uri): String = "application/vnd.sqlite3"

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    private fun checkpoint(dbFile: File) {
        val db = SQLiteDatabase.openDatabase(
            dbFile.absolutePath,
            null,
            SQLiteDatabase.OPEN_READWRITE,
        )
        try {
            db.rawQuery("PRAGMA wal_checkpoint(TRUNCATE)", null).use { }
        } finally {
            db.close()
        }
    }

    companion object {
        const val DB_NAME = "ludoteca.db"
    }
}
