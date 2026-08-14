package com.ludoteca.ludoteca_mobile

import android.content.Context
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileNotFoundException

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method == "cloneFromProd") {
                try {
                    cloneFromProd(applicationContext)
                    result.success(null)
                } catch (e: FileNotFoundException) {
                    val code = if (e.message == "no_database") "no_database" else "prod_not_installed"
                    result.error(code, e.message, null)
                } catch (e: SecurityException) {
                    result.error("permission_denied", e.message, null)
                } catch (e: Exception) {
                    result.error("copy_failed", e.message, null)
                }
            } else {
                result.notImplemented()
            }
        }
    }

    private fun cloneFromProd(context: Context) {
        val dest = context.getDatabasePath(DB_NAME)
        dest.parentFile?.mkdirs()

        val uri = Uri.parse("content://$PROD_AUTHORITY/ludoteca.db")
        val input = try {
            context.contentResolver.openInputStream(uri)
        } catch (e: SecurityException) {
            throw e
        } catch (e: FileNotFoundException) {
            throw e
        } catch (_: Exception) {
            throw FileNotFoundException("prod_not_installed")
        } ?: throw FileNotFoundException("prod_not_installed")

        input.use { src ->
            dest.outputStream().use { out -> src.copyTo(out) }
        }

        File(dest.path + "-wal").delete()
        File(dest.path + "-shm").delete()
        File(dest.path + "-journal").delete()
    }

    companion object {
        const val CHANNEL = "com.ludoteca.ludoteca_mobile/db_clone"
        private const val PROD_AUTHORITY = "com.ludoteca.ludoteca_mobile.localdb"
        private const val DB_NAME = "ludoteca.db"
    }
}
