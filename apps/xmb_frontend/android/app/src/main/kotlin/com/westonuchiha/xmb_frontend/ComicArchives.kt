package com.westonuchiha.xmb_frontend

import com.github.junrar.Archive
import com.github.junrar.exception.UnsupportedRarV5Exception
import org.apache.commons.compress.archivers.sevenz.SevenZFile
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

/// RAR (.cbr) and 7z (.cb7) comics, page by page like the PC: the page list
/// is read when a book opens; each page is unpacked into a cache folder the
/// first time it's shown. In solid archives (every page packed together)
/// the pages before it come out on the way and are kept.
class ComicArchives(private val cacheRoot: File) {

    private fun isRar(f: File): Boolean = f.inputStream().use {
        val b = ByteArray(4)
        it.read(b) == 4 && b[0] == 'R'.code.toByte() && b[1] == 'a'.code.toByte() &&
            b[2] == 'r'.code.toByte() && b[3] == '!'.code.toByte()
    }

    /// The book's cache folder (by path, size and date, so a changed file
    /// starts again). Only the last few books are kept.
    private fun cacheFor(f: File): File {
        val key = "${f.absolutePath}|${f.length()}|${f.lastModified()}"
        val hex = MessageDigest.getInstance("SHA-1").digest(key.toByteArray())
            .joinToString("") { "%02x".format(it) }.take(16)
        val dir = File(cacheRoot, "comics/$hex")
        if (!dir.exists()) {
            val all = File(cacheRoot, "comics").listFiles()?.sortedBy { it.lastModified() } ?: emptyList()
            for (old in all.dropLast(4)) old.deleteRecursively()
        }
        dir.mkdirs()
        dir.setLastModified(System.currentTimeMillis())
        return dir
    }

    /// Every file in the book (names with '/').
    fun list(path: String): List<String> {
        val f = File(path)
        return if (isRar(f)) {
            try {
                Archive(f).use { a ->
                    a.fileHeaders.filter { !it.isDirectory }.map { it.fileName.replace('\\', '/') }
                }
            } catch (e: UnsupportedRarV5Exception) {
                throw IllegalStateException("rar5")
            }
        } else {
            SevenZFile.builder().setFile(f).get().use { z ->
                z.entries.filter { !it.isDirectory }.map { it.name.replace('\\', '/') }
            }
        }
    }

    /// The unpacked file of [name] (unpacked now if it isn't yet).
    fun page(path: String, name: String): String {
        val f = File(path)
        val dir = cacheFor(f)
        fun out(n: String) = File(dir, n.replace('/', '_').replace('\\', '_'))
        val want = out(name)
        if (want.exists() && want.length() > 0) return want.absolutePath
        if (isRar(f)) {
            Archive(f).use { a ->
                val solid = a.mainHeader.isSolid
                for (h in a.fileHeaders) {
                    if (h.isDirectory) continue
                    val n = h.fileName.replace('\\', '/')
                    val target = n == name
                    val o = out(n)
                    if (target || (solid && !o.exists())) {
                        val tmp = File(o.path + ".part")
                        FileOutputStream(tmp).use { s -> a.extractFile(h, s) }
                        tmp.renameTo(o)
                    } else if (solid) {
                        // Already unpacked: still has to be read through.
                        a.extractFile(h, NullStream)
                    }
                    if (target) break
                }
            }
        } else {
            SevenZFile.builder().setFile(f).get().use { z ->
                val e = z.entries.firstOrNull { it.name.replace('\\', '/') == name }
                    ?: throw IllegalStateException("no such page")
                val tmp = File(want.path + ".part")
                z.getInputStream(e).use { i -> FileOutputStream(tmp).use { o -> i.copyTo(o) } }
                tmp.renameTo(want)
            }
        }
        return want.absolutePath
    }

    private object NullStream : java.io.OutputStream() {
        override fun write(b: Int) {}
        override fun write(b: ByteArray, off: Int, len: Int) {}
    }
}
