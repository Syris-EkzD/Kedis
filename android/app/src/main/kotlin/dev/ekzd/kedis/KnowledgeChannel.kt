package dev.ekzd.kedis

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.StatFs
import android.provider.OpenableColumns
import android.system.Os
import android.text.Html
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.kiwix.libkiwix.JNIKiwix
import org.kiwix.libzim.Archive
import org.kiwix.libzim.Query
import org.kiwix.libzim.Searcher
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

/** An independent, local-only archive reader. Never opens the task database. */
internal class KnowledgeChannel(
    private val activity: Activity,
    messenger: BinaryMessenger,
) {
    private val context = activity.applicationContext
    private val channel = MethodChannel(messenger, "kedis/knowledge")
    private var pickerResult: MethodChannel.Result? = null

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "importArchive" -> chooseArchive(result)
            "status" -> submit(result) { status(context) }
            "remove" -> submit(result) {
                val file = archiveFile(context)
                check(!file.exists() || file.delete()) { "Cannot remove the local archive." }
                null
            }
            "search" -> {
                val query = call.argument<String>("query")?.trim().orEmpty()
                if (query.isEmpty() || query.length > 200) {
                    result.error("invalid_query", "Enter 1–200 characters.", null)
                } else {
                    submit(result) { withArchive(context) { search(it, query) } }
                }
            }
            "read" -> {
                val path = call.argument<String>("path").orEmpty()
                val uuid = call.argument<String>("uuid").orEmpty()
                if (path.isEmpty() || path.length > 2048 || uuid.isEmpty()) {
                    result.error("invalid_article", "Invalid article identity.", null)
                } else {
                    submit(result) {
                        withArchive(context) { archive ->
                            check(archive.uuid == uuid) { "The archive changed. Search again." }
                            readArticle(archive, path)
                        }
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    @Suppress("DEPRECATION")
    private fun chooseArchive(result: MethodChannel.Result) {
        if (pickerResult != null) {
            result.error("busy", "An archive picker is already open.", null)
            return
        }
        pickerResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                addCategory(Intent.CATEGORY_OPENABLE)
                type = "*/*"
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            activity.startActivityForResult(intent, PICK_ARCHIVE)
        } catch (e: Exception) {
            pickerResult = null
            result.error("picker_failed", "Cannot open the document picker.", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_ARCHIVE) return false
        val result = pickerResult ?: return true
        pickerResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
        } else {
            submit(result) { importArchive(context, uri) }
        }
        return true
    }

    fun close() {
        channel.setMethodCallHandler(null)
        pickerResult?.success(null)
        pickerResult = null
    }

    private fun submit(result: MethodChannel.Result, action: () -> Any?) {
        worker.execute {
            try {
                result.success(action())
            } catch (e: LinkageError) {
                result.error("native_unavailable", "The native ZIM reader could not load.", null)
            } catch (e: Exception) {
                result.error("knowledge_error", e.message ?: "Knowledge operation failed.", null)
            }
        }
    }

    companion object {
        private const val PICK_ARCHIVE = 7314
        private const val MAX_ARCHIVE_BYTES = 2L * 1024 * 1024 * 1024
        private const val FREE_SPACE_RESERVE = 128L * 1024 * 1024
        private const val MAX_HTML_BYTES = 2L * 1024 * 1024
        private const val MAX_TEXT_CHARS = 40_000
        // Serialize all archive operations, including across Activity recreation.
        private val worker = Executors.newSingleThreadExecutor()
        private var loaded = false

        private fun ensureLoaded(context: Context) {
            if (!loaded) {
                JNIKiwix(context)
                loaded = true
            }
        }

        private fun archiveFile(context: Context): File =
            File(context.noBackupFilesDir, "companion/knowledge.zim")

        private fun <T> open(context: Context, file: File, action: (Archive) -> T): T {
            check(file.isFile) { "No local archive. Import a ZIM file first." }
            ensureLoaded(context)
            val archive = Archive(file.absolutePath)
            try {
                check(!archive.isMultiPart) { "Split ZIM archives are not supported." }
                check(archive.hasFulltextIndex()) { "This archive has no full-text index." }
                return action(archive)
            } finally {
                archive.dispose()
            }
        }

        private fun <T> withArchive(context: Context, action: (Archive) -> T): T =
            open(context, archiveFile(context), action)

        private fun metadata(archive: Archive, key: String): String =
            if (archive.metadataKeys.contains(key)) archive.getMetadata(key).take(500) else ""

        private fun describe(archive: Archive): Map<String, Any> = mapOf(
            "uuid" to archive.uuid,
            "title" to metadata(archive, "Title").ifBlank { "Local ZIM archive" },
            "name" to metadata(archive, "Name"),
            "date" to metadata(archive, "Date"),
            "creator" to metadata(archive, "Creator"),
            "publisher" to metadata(archive, "Publisher"),
            "source" to metadata(archive, "Source"),
            "license" to metadata(archive, "License"),
            "bytes" to archive.filesize,
        )

        private fun status(context: Context): Map<String, Any>? {
            if (!archiveFile(context).exists()) return null
            return withArchive(context, ::describe)
        }

        private fun importArchive(context: Context, uri: Uri): Map<String, Any> {
            val target = archiveFile(context)
            val directory = requireNotNull(target.parentFile)
            check(directory.isDirectory || directory.mkdirs()) { "Cannot create archive storage." }
            val staging = File(directory, "incoming.zim")
            check(!staging.exists() || staging.delete()) { "Cannot clear incomplete import." }

            val resolver = context.contentResolver
            val declaredSize = resolver.query(uri, arrayOf(OpenableColumns.SIZE), null, null, null)
                ?.use { cursor ->
                    if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getLong(0) else null
                }
            if (declaredSize != null && declaredSize >= 0) {
                require(declaredSize <= MAX_ARCHIVE_BYTES) { "M1 supports archives up to 2 GiB." }
                check(StatFs(directory.path).availableBytes - FREE_SPACE_RESERVE >= declaredSize) {
                    "Not enough storage for an independent archive copy."
                }
            }

            try {
                val input = resolver.openInputStream(uri)
                    ?: error("Cannot read the selected document.")
                input.use { source ->
                    FileOutputStream(staging).use { destination ->
                        val buffer = ByteArray(256 * 1024)
                        var total = 0L
                        while (true) {
                            val count = source.read(buffer)
                            if (count < 0) break
                            if (count == 0) continue
                            total += count
                            require(total <= MAX_ARCHIVE_BYTES) { "M1 supports archives up to 2 GiB." }
                            check(StatFs(directory.path).availableBytes - FREE_SPACE_RESERVE >= count) {
                                "Not enough storage for the archive copy."
                            }
                            destination.write(buffer, 0, count)
                        }
                        check(total > 0L) { "The selected document is empty." }
                        destination.fd.sync()
                    }
                }
                val info = open(context, staging) { archive ->
                    check(archive.hasChecksum() && archive.check()) {
                        "The ZIM checksum is missing or invalid."
                    }
                    check(archive.articleCount > 0) { "The archive contains no articles." }
                    describe(archive)
                }
                // Atomic same-directory replacement only after the copy passes validation.
                Os.rename(staging.absolutePath, target.absolutePath)
                return info
            } finally {
                if (staging.exists()) staging.delete()
            }
        }

        private fun search(archive: Archive, text: String): List<Map<String, String>> {
            val searcher = Searcher(archive)
            try {
                val query = Query(text)
                try {
                    val search = searcher.search(query)
                    try {
                        val results = search.getResults(0, 20)
                        try {
                            val matches = mutableListOf<Map<String, String>>()
                            while (results.hasNext() && matches.size < 20) {
                                val entry = results.next()
                                matches.add(mapOf(
                                    "title" to entry.title,
                                    "path" to entry.path,
                                    "uuid" to archive.uuid,
                                ))
                            }
                            return matches
                        } finally {
                            results.dispose()
                        }
                    } finally {
                        search.dispose()
                    }
                } finally {
                    query.dispose()
                }
            } finally {
                searcher.dispose()
            }
        }

        private fun readArticle(archive: Archive, path: String): Map<String, Any> {
            val entry = archive.getEntryByPath(path)
            val item = entry.getItem(true)
            check(item.mimetype.startsWith("text/html") || item.mimetype.startsWith("text/plain")) {
                "This record is not a readable text article."
            }
            check(item.size <= MAX_HTML_BYTES) { "This article exceeds the M1 reading limit." }
            val blob = item.data
            val raw = try {
                String(blob.data, Charsets.UTF_8)
            } finally {
                blob.dispose()
            }
            // Return only plain text. No WebView, scripts, active links or image loads.
            val text = if (item.mimetype.startsWith("text/html")) {
                Html.fromHtml(raw, Html.FROM_HTML_MODE_LEGACY).toString()
            } else raw
            check(text.isNotBlank()) { "No readable text was found." }
            return mapOf(
                "title" to entry.title,
                "path" to path,
                "resolvedPath" to item.path,
                "archive" to describe(archive),
                "text" to text.trim().take(MAX_TEXT_CHARS),
                "truncated" to (text.trim().length > MAX_TEXT_CHARS),
            )
        }
    }
}
