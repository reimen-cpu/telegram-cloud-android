package com.telegram.cloud.data.backup

import android.content.Context
import android.util.Base64
import android.util.Log
import com.telegram.cloud.data.local.CloudDatabase
import com.telegram.cloud.data.prefs.BotConfig
import com.telegram.cloud.data.prefs.ConfigStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import org.json.JSONObject
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.PBEKeySpec
import javax.crypto.spec.SecretKeySpec
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

private const val TAG = "BackupManager"
private const val ENVMANAGER_SALT = "TELEGRAM_CLOUD_SALT"
private const val ENVMANAGER_PBKDF2_ITERATIONS = 100000

class BackupManager(
    private val context: Context,
    private val configStore: ConfigStore,
    private val database: CloudDatabase
) {

    private val cacheDir: File get() = File(context.cacheDir, "tgcloud")

    suspend fun createBackup(targetFile: File, password: String? = null) =
        withContext(Dispatchers.IO) {
            val config = configStore.configFlow.first()
                ?: error("Configura tokens antes de generar el backup")

            val workDir = File(cacheDir, "backup_pack").apply {
                if (exists()) deleteRecursively()
                mkdirs()
            }

            val envFile = File(workDir, ".env")
            envFile.writeText(buildEnvFile(config))

            val dbSource = context.getDatabasePath("cloud.db")
            val dbDir = File(workDir, "database").apply { mkdirs() }
            val dbTarget = File(dbDir, "telegram_cloud.db")
            if (dbSource.exists()) {
                dbSource.copyTo(dbTarget, overwrite = true)
            } else {
                dbTarget.delete()
            }

            val encrypted = !password.isNullOrBlank()
            if (encrypted) {
                val pwd = password!!
                encryptFile(envFile, File(workDir, ".env.enc"), pwd)
                encryptFile(dbTarget, File(workDir, "telegram_cloud.db.enc"), pwd)
                envFile.delete()
                dbTarget.delete()
            }

            val manifest = JSONObject().apply { put("encrypted", encrypted) }
            File(workDir, "backup_manifest.json").writeText(manifest.toString())

            zipDirectory(workDir, targetFile)
            workDir.deleteRecursively()
        }

    suspend fun restoreBackup(sourceFile: File, password: String? = null) =
        withContext(Dispatchers.IO) {
            Log.i(TAG, "restoreBackup: sourceFile=${sourceFile.absolutePath}, hasPassword=${password != null}")
            
            val workDir = File(cacheDir, "backup_unpack").apply {
                if (exists()) deleteRecursively()
                mkdirs()
            }
            Log.i(TAG, "restoreBackup: workDir=${workDir.absolutePath}")

            unzip(sourceFile, workDir)
            
            // Log extracted contents
            Log.i(TAG, "restoreBackup: Extracted contents:")
            workDir.walkTopDown().forEach { file ->
                Log.i(TAG, "  - ${file.relativeTo(workDir).path} (${file.length()} bytes)")
            }

            val manifestFile = File(workDir, "backup_manifest.json")
            val encrypted = if (manifestFile.exists()) {
                val manifestContent = manifestFile.readText()
                Log.i(TAG, "restoreBackup: manifest=$manifestContent")
                JSONObject(manifestContent).optBoolean("encrypted", false)
            } else {
                Log.i(TAG, "restoreBackup: No manifest found, assuming unencrypted")
                false
            }
            Log.i(TAG, "restoreBackup: encrypted=$encrypted")

            val envBytes: ByteArray
            val dbBytes: ByteArray

            if (encrypted) {
                val pwd = password ?: error("El backup requiere contraseña")
                Log.i(TAG, "restoreBackup: Decrypting .env.enc with password length=${pwd.length}")
                
                val envEncFile = File(workDir, ".env.enc")
                Log.i(TAG, "restoreBackup: .env.enc exists=${envEncFile.exists()}, size=${envEncFile.length()}")
                
                envBytes = decryptFile(envEncFile, pwd)
                Log.i(TAG, "restoreBackup: Decrypted .env, size=${envBytes.size}")
                
                val dbEncFile = File(workDir, "telegram_cloud.db.enc")
                Log.i(TAG, "restoreBackup: telegram_cloud.db.enc exists=${dbEncFile.exists()}, size=${dbEncFile.length()}")
                
                dbBytes = decryptFile(dbEncFile, pwd)
                Log.i(TAG, "restoreBackup: Decrypted db, size=${dbBytes.size}")
            } else {
                val envFile = File(workDir, ".env")
                Log.i(TAG, "restoreBackup: .env exists=${envFile.exists()}")
                envBytes = envFile.takeIf { it.exists() }?.readBytes()
                    ?: error("Backup inválido: falta .env")
                    
                val dbFile = File(workDir, "database/telegram_cloud.db")
                Log.i(TAG, "restoreBackup: database/telegram_cloud.db exists=${dbFile.exists()}")
                dbBytes = dbFile.takeIf { it.exists() }?.readBytes()
                    ?: error("Backup inválido: falta database/telegram_cloud.db")
            }

            val envContent = String(envBytes)
            Log.i(TAG, "restoreBackup: .env content (first 500 chars):\n${envContent.take(500)}")
            
            val envMap = parseEnv(envContent)
            Log.i(TAG, "restoreBackup: Parsed ${envMap.size} env variables")
            envMap.forEach { (key, value) ->
                Log.i(TAG, "restoreBackup: ENV $key = ${value.take(20)}...")
            }
            
            // Collect all tokens: BOT_TOKEN, BOT_TOKEN_*, and ADDITIONAL_BOT_TOKENS (comma-separated)
            val tokensList = mutableListOf<String>()
            
            // Primary BOT_TOKEN
            envMap["BOT_TOKEN"]?.takeIf { it.isNotBlank() }?.let { tokensList.add(it) }
            
            // BOT_TOKEN_1, BOT_TOKEN_2, etc.
            envMap.filterKeys { it.startsWith("BOT_TOKEN_") }
                .toSortedMap(compareBy { it.removePrefix("BOT_TOKEN_").toIntOrNull() ?: 999 })
                .values
                .filter { it.isNotBlank() }
                .forEach { tokensList.add(it) }
            
            // ADDITIONAL_BOT_TOKENS (comma-separated)
            envMap["ADDITIONAL_BOT_TOKENS"]?.split(",")
                ?.map { it.trim() }
                ?.filter { it.isNotBlank() }
                ?.forEach { if (it !in tokensList) tokensList.add(it) }
            
            val tokens = tokensList.distinct()
            val channel = envMap["CHANNEL_ID"].orEmpty()
            
            Log.i(TAG, "restoreBackup: Found ${tokens.size} tokens, channelId='${channel.take(20)}...'")
            tokens.forEachIndexed { idx, token ->
                Log.i(TAG, "restoreBackup: Token[$idx] = ${token.take(20)}...")
            }
            
            require(tokens.isNotEmpty() && channel.isNotBlank()) {
                "Backup inválido: faltan tokens o channel id (tokens=${tokens.size}, channel=${channel.isNotBlank()})"
            }

            Log.i(TAG, "restoreBackup: Saving config...")
            configStore.save(
                BotConfig(
                    tokens = tokens,
                    channelId = channel,
                    chatId = envMap["CHAT_ID"]
                )
            )
            Log.i(TAG, "restoreBackup: Config saved")

            // Detect backup type and restore accordingly
            val tempDbPath = File(cacheDir, "temp_restore.db")
            tempDbPath.parentFile?.mkdirs()
            FileOutputStream(tempDbPath).use { it.write(dbBytes) }
            Log.i(TAG, "restoreBackup: Temp database saved to ${tempDbPath.absolutePath}")
            
            // Get DB encryption key from env if present
            val dbEncryptionKey = envMap["DB_ENCRYPTION_KEY"]
            Log.i(TAG, "restoreBackup: DB_ENCRYPTION_KEY present=${dbEncryptionKey != null}")
            
            // Detect backup type
            val backupType = detectBackupType(tempDbPath, dbEncryptionKey)
            Log.i(TAG, "restoreBackup: Detected backup type: $backupType")
            
            val targetDb = context.getDatabasePath("cloud.db")
            
            when (backupType) {
                "android" -> {
                    // Android backup: copy database and let Room apply migrations
                    Log.i(TAG, "restoreBackup: Restoring Android backup")
                    restoreAndroidBackup(tempDbPath, targetDb, dbEncryptionKey)
                }
                "desktop" -> {
                    // Desktop backup: migrate data to Android format
                    Log.i(TAG, "restoreBackup: Migrating desktop backup")
                    migrateDesktopDatabase(tempDbPath, targetDb, channel, dbEncryptionKey)
                }
                else -> {
                    // Unknown type: try desktop migration as fallback
                    Log.w(TAG, "restoreBackup: Unknown backup type, attempting desktop migration")
                    migrateDesktopDatabase(tempDbPath, targetDb, channel, dbEncryptionKey)
                }
            }
            
            tempDbPath.delete()
            workDir.deleteRecursively()
            
            // Invalidate Room's cache so it picks up the migrated data
            database.invalidateAllTables()
            Log.i(TAG, "restoreBackup: Invalidated Room cache")
            
            Log.i(TAG, "restoreBackup: Complete!")
        }

    /**
     * Detects the type of backup database (Android or Desktop) by checking for characteristic tables.
     * Returns "android" if cloud_files and room_master_table exist, "desktop" if files table exists, null otherwise.
     */
    private suspend fun detectBackupType(sourceDb: File, dbEncryptionKey: String? = null): String? = withContext(Dispatchers.IO) {
        try {
            val tables = mutableListOf<String>()
            
            if (dbEncryptionKey != null) {
                // Encrypted database - use SQLCipher
                System.loadLibrary("sqlcipher")
                var cipherDb: net.zetetic.database.sqlcipher.SQLiteDatabase? = null
                
                // Try to open with default SQLCipher settings
                try {
                    cipherDb = net.zetetic.database.sqlcipher.SQLiteDatabase.openDatabase(
                        sourceDb.absolutePath,
                        dbEncryptionKey,
                        null,
                        net.zetetic.database.sqlcipher.SQLiteDatabase.OPEN_READONLY,
                        null,
                        null
                    )
                    
                    val tablesCursor = cipherDb.rawQuery(
                        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
                        null
                    )
                    while (tablesCursor.moveToNext()) {
                        tables.add(tablesCursor.getString(0))
                    }
                    tablesCursor.close()
                    cipherDb.close()
                } catch (e: Exception) {
                    Log.w(TAG, "detectBackupType: Failed to open encrypted DB for detection: ${e.message}")
                    cipherDb?.close()
                    return@withContext null
                }
            } else {
                // Unencrypted database
                val conn = android.database.sqlite.SQLiteDatabase.openDatabase(
                    sourceDb.absolutePath,
                    null,
                    android.database.sqlite.SQLiteDatabase.OPEN_READONLY
                )
                
                val tablesCursor = conn.rawQuery(
                    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
                    null
                )
                while (tablesCursor.moveToNext()) {
                    tables.add(tablesCursor.getString(0))
                }
                tablesCursor.close()
                conn.close()
            }
            
            Log.i(TAG, "detectBackupType: Found tables: $tables")
            
            // Android backup: has cloud_files and room_master_table
            if (tables.contains("cloud_files") && tables.contains("room_master_table")) {
                Log.i(TAG, "detectBackupType: Detected Android backup")
                return@withContext "android"
            }
            
            // Desktop backup: has files table
            if (tables.contains("files")) {
                Log.i(TAG, "detectBackupType: Detected Desktop backup")
                return@withContext "desktop"
            }
            
            Log.w(TAG, "detectBackupType: Unknown backup type")
            return@withContext null
        } catch (e: Exception) {
            Log.e(TAG, "detectBackupType: Error detecting backup type", e)
            return@withContext null
        }
    }

    /**
     * Restores an Android backup by copying the database and ensuring Room can apply migrations.
     * For encrypted databases, uses Room DAO directly instead of copying.
     */
    private suspend fun restoreAndroidBackup(sourceDb: File, targetDb: File, dbEncryptionKey: String? = null) = withContext(Dispatchers.IO) {
        Log.i(TAG, "restoreAndroidBackup: Starting Android backup restoration")
        
        try {
            if (dbEncryptionKey != null) {
                // Encrypted database: use Room DAO to migrate data
                Log.i(TAG, "restoreAndroidBackup: Encrypted database, using Room DAO migration")
                System.loadLibrary("sqlcipher")
                
                // Try to open encrypted source database
                var cipherDb: net.zetetic.database.sqlcipher.SQLiteDatabase? = null
                val configs = listOf(
                    mapOf("key" to dbEncryptionKey, "postKeyPragmas" to listOf(
                        "PRAGMA cipher_page_size = 4096",
                        "PRAGMA kdf_iter = 256000",
                        "PRAGMA cipher_hmac_algorithm = HMAC_SHA1",
                        "PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA1"
                    )),
                    mapOf("key" to dbEncryptionKey, "postKeyPragmas" to listOf<String>())
                )
                
                for (config in configs) {
                    try {
                        val keyToUse = config["key"] as String
                        @Suppress("UNCHECKED_CAST")
                        val postKeyPragmas = config["postKeyPragmas"] as List<String>
                        
                        val hook = object : net.zetetic.database.sqlcipher.SQLiteDatabaseHook {
                            override fun preKey(connection: net.zetetic.database.sqlcipher.SQLiteConnection) {}
                            override fun postKey(connection: net.zetetic.database.sqlcipher.SQLiteConnection) {
                                for (pragma in postKeyPragmas) {
                                    try {
                                        connection.execute(pragma, null, null)
                                    } catch (e: Exception) {
                                        Log.w(TAG, "restoreAndroidBackup: postKey failed $pragma: ${e.message}")
                                    }
                                }
                            }
                        }
                        
                        cipherDb = net.zetetic.database.sqlcipher.SQLiteDatabase.openDatabase(
                            sourceDb.absolutePath,
                            keyToUse,
                            null,
                            net.zetetic.database.sqlcipher.SQLiteDatabase.OPEN_READONLY,
                            null,
                            hook
                        )
                        Log.i(TAG, "restoreAndroidBackup: Successfully opened encrypted database")
                        break
                    } catch (e: Exception) {
                        Log.w(TAG, "restoreAndroidBackup: Failed to open with config: ${e.message}")
                    }
                }
                
                if (cipherDb == null) {
                    throw Exception("Failed to open encrypted Android backup database")
                }
                
                // Clear existing Room data
                database.cloudFileDao().clear()
                database.uploadTaskDao().clear()
                database.downloadTaskDao().clear()
                database.galleryMediaDao().clear()
                
                // Migrate data from encrypted Android backup using Room DAO
                migrateFromAndroidBackup(cipherDb)
                cipherDb.close()
                
                Log.i(TAG, "restoreAndroidBackup: Encrypted Android backup restoration complete")
                return@withContext
            }
            
            // Unencrypted database: copy and set version
            // Close Room database connection if open
            database.close()
            
            // Delete existing database files
            targetDb.delete()
            File(targetDb.absolutePath + "-shm").delete()
            File(targetDb.absolutePath + "-wal").delete()
            targetDb.parentFile?.mkdirs()
            
            // Copy the backup database
            sourceDb.copyTo(targetDb, overwrite = true)
            Log.i(TAG, "restoreAndroidBackup: Database copied to ${targetDb.absolutePath}")
            
            // Open the copied database to check and set version
            val conn = android.database.sqlite.SQLiteDatabase.openDatabase(
                targetDb.absolutePath,
                null,
                android.database.sqlite.SQLiteDatabase.OPEN_READWRITE
            )
            
            // Check current version
            val versionCursor = conn.rawQuery("PRAGMA user_version", null)
            var currentVersion = 0
            if (versionCursor.moveToFirst()) {
                currentVersion = versionCursor.getInt(0)
            }
            versionCursor.close()
            
            Log.i(TAG, "restoreAndroidBackup: Current database version: $currentVersion")
            
            // If version is 0 or not set, detect from schema or set to 1
            if (currentVersion == 0) {
                // Try to detect version by checking which columns exist
                var detectedVersion = 1
                
                // Check for migration 4_5 columns in upload_tasks
                val uploadColumnsCursor = conn.rawQuery(
                    "PRAGMA table_info(upload_tasks)",
                    null
                )
                val uploadColumns = mutableSetOf<String>()
                while (uploadColumnsCursor.moveToNext()) {
                    val colName = uploadColumnsCursor.getString(1)
                    uploadColumns.add(colName)
                }
                uploadColumnsCursor.close()
                
                if (uploadColumns.contains("file_id") && 
                    uploadColumns.contains("completed_chunks_json") && 
                    uploadColumns.contains("token_offset")) {
                    detectedVersion = 5
                } else if (uploadColumns.isNotEmpty()) {
                    // Has upload_tasks table but not migration 4_5 columns, check for other migrations
                    val galleryColumnsCursor = conn.rawQuery(
                        "PRAGMA table_info(gallery_media)",
                        null
                    )
                    val galleryColumns = mutableSetOf<String>()
                    while (galleryColumnsCursor.moveToNext()) {
                        val colName = galleryColumnsCursor.getString(1)
                        galleryColumns.add(colName)
                    }
                    galleryColumnsCursor.close()
                    
                    if (galleryColumns.contains("telegram_file_unique_id") && 
                        galleryColumns.contains("telegram_uploader_tokens")) {
                        detectedVersion = 4
                    } else if (galleryColumns.isNotEmpty()) {
                        detectedVersion = 3
                    } else {
                        // Check for uploader_tokens in cloud_files
                        val cloudColumnsCursor = conn.rawQuery(
                            "PRAGMA table_info(cloud_files)",
                            null
                        )
                        val cloudColumns = mutableSetOf<String>()
                        while (cloudColumnsCursor.moveToNext()) {
                            val colName = cloudColumnsCursor.getString(1)
                            cloudColumns.add(colName)
                        }
                        cloudColumnsCursor.close()
                        
                        if (cloudColumns.contains("uploader_tokens")) {
                            detectedVersion = 2
                        }
                    }
                }
                
                Log.i(TAG, "restoreAndroidBackup: Detected version: $detectedVersion")
                conn.execSQL("PRAGMA user_version = $detectedVersion")
                Log.i(TAG, "restoreAndroidBackup: Set user_version to $detectedVersion (Room will apply migrations if needed)")
            }
            
            conn.close()
            
            Log.i(TAG, "restoreAndroidBackup: Android backup restoration complete")
        } catch (e: Exception) {
            Log.e(TAG, "restoreAndroidBackup: Error restoring Android backup", e)
            throw e
        }
    }

    /**
     * Migrates a desktop SQLite database to Android Room format.
     * Desktop table: files (file_id, file_name, file_size, upload_date, mime_type, message_id, telegram_file_id)
     * Android table: cloud_files (telegram_message_id, file_id, file_unique_id, file_name, mime_type, size_bytes, uploaded_at, caption, share_link, checksum)
     */
    private suspend fun migrateDesktopDatabase(sourceDb: File, targetDb: File, channelId: String, dbEncryptionKey: String? = null) {
        Log.i(TAG, "migrateDesktopDatabase: Starting migration from ${sourceDb.absolutePath}")
        Log.i(TAG, "migrateDesktopDatabase: Source file exists=${sourceDb.exists()}, size=${sourceDb.length()}")
        Log.i(TAG, "migrateDesktopDatabase: Encrypted=${dbEncryptionKey != null}")
        
        // For encrypted databases, we use Room DAO directly (don't delete the DB file)
        // For unencrypted, we recreate the DB file
        if (dbEncryptionKey == null) {
            // Delete existing Android database to start fresh (only for unencrypted migration)
            targetDb.delete()
            File(targetDb.absolutePath + "-shm").delete()
            File(targetDb.absolutePath + "-wal").delete()
            targetDb.parentFile?.mkdirs()
        }
        
        try {
            // Open source (desktop) database - may be encrypted with SQLCipher
            val sourceConn: android.database.sqlite.SQLiteDatabase
            
            if (dbEncryptionKey != null) {
                // Database is encrypted with SQLCipher - use SQLCipher library
                Log.i(TAG, "migrateDesktopDatabase: Opening encrypted database with SQLCipher")
                Log.i(TAG, "migrateDesktopDatabase: Key length=${dbEncryptionKey.length}")
                System.loadLibrary("sqlcipher")
                
                // Desktop uses SQLCipher with specific settings
                // Try different compatibility modes
                var cipherDb: net.zetetic.database.sqlcipher.SQLiteDatabase? = null
                var lastError: Exception? = null
                
                // Desktop uses: PRAGMA key = 'hexstring' then PRAGMA cipher_* AFTER key
                // The key is a 64-char hex string used as passphrase (not raw key)
                // CRITICAL: Desktop sets cipher pragmas AFTER the key, not before!
                val configs = listOf(
                    // Config 1: Desktop exact match - passphrase + postKey pragmas
                    mapOf(
                        "name" to "Desktop-exact-postKey",
                        "key" to dbEncryptionKey,
                        "preKeyPragmas" to listOf<String>(),
                        "postKeyPragmas" to listOf(
                            "PRAGMA cipher_page_size = 4096",
                            "PRAGMA kdf_iter = 256000",
                            "PRAGMA cipher_hmac_algorithm = HMAC_SHA1",
                            "PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA1"
                        )
                    ),
                    // Config 2: SQLCipher 4 defaults with passphrase
                    mapOf(
                        "name" to "SQLCipher4-passphrase",
                        "key" to dbEncryptionKey,
                        "preKeyPragmas" to listOf<String>(),
                        "postKeyPragmas" to listOf<String>()
                    ),
                    // Config 3: Desktop settings in preKey (old approach)
                    mapOf(
                        "name" to "Desktop-custom-preKey",
                        "key" to dbEncryptionKey,
                        "preKeyPragmas" to listOf(
                            "PRAGMA cipher_page_size = 4096",
                            "PRAGMA kdf_iter = 256000",
                            "PRAGMA cipher_hmac_algorithm = HMAC_SHA1",
                            "PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA1"
                        ),
                        "postKeyPragmas" to listOf<String>()
                    ),
                    // Config 4: Try as raw hex key (x'...' format) with postKey
                    mapOf(
                        "name" to "Desktop-rawkey-postKey",
                        "key" to "x'$dbEncryptionKey'",
                        "preKeyPragmas" to listOf<String>(),
                        "postKeyPragmas" to listOf(
                            "PRAGMA cipher_page_size = 4096",
                            "PRAGMA kdf_iter = 256000",
                            "PRAGMA cipher_hmac_algorithm = HMAC_SHA1",
                            "PRAGMA cipher_kdf_algorithm = PBKDF2_HMAC_SHA1"
                        )
                    ),
                    // Config 5: Raw key default
                    mapOf(
                        "name" to "SQLCipher4-rawkey",
                        "key" to "x'$dbEncryptionKey'",
                        "preKeyPragmas" to listOf<String>(),
                        "postKeyPragmas" to listOf<String>()
                    ),
                    // Config 6: SQLCipher 3 compatibility
                    mapOf(
                        "name" to "SQLCipher3-compat",
                        "key" to dbEncryptionKey,
                        "preKeyPragmas" to listOf("PRAGMA cipher_compatibility = 3"),
                        "postKeyPragmas" to listOf<String>()
                    ),
                    // Config 7: cipher_default_settings approach
                    mapOf(
                        "name" to "Desktop-cipher-default",
                        "key" to dbEncryptionKey,
                        "preKeyPragmas" to listOf(
                            "PRAGMA cipher_default_page_size = 4096",
                            "PRAGMA cipher_default_kdf_iter = 256000",
                            "PRAGMA cipher_default_hmac_algorithm = HMAC_SHA1",
                            "PRAGMA cipher_default_kdf_algorithm = PBKDF2_HMAC_SHA1"
                        ),
                        "postKeyPragmas" to listOf<String>()
                    )
                )
                
                for (config in configs) {
                    val configName = config["name"] as String
                    val keyToUse = config["key"] as String
                    @Suppress("UNCHECKED_CAST")
                    val preKeyPragmas = config["preKeyPragmas"] as List<String>
                    @Suppress("UNCHECKED_CAST")
                    val postKeyPragmas = config["postKeyPragmas"] as List<String>
                    
                    Log.i(TAG, "migrateDesktopDatabase: Trying config '$configName' with key format: ${keyToUse.take(10)}...")
                    
                    try {
                        val hook = object : net.zetetic.database.sqlcipher.SQLiteDatabaseHook {
                            override fun preKey(connection: net.zetetic.database.sqlcipher.SQLiteConnection) {
                                for (pragma in preKeyPragmas) {
                                    try {
                                        connection.execute(pragma, null, null)
                                        Log.d(TAG, "migrateDesktopDatabase: preKey executed $pragma")
                                    } catch (e: Exception) {
                                        Log.w(TAG, "migrateDesktopDatabase: preKey failed $pragma: ${e.message}")
                                    }
                                }
                            }
                            override fun postKey(connection: net.zetetic.database.sqlcipher.SQLiteConnection) {
                                for (pragma in postKeyPragmas) {
                                    try {
                                        connection.execute(pragma, null, null)
                                        Log.d(TAG, "migrateDesktopDatabase: postKey executed $pragma")
                                    } catch (e: Exception) {
                                        Log.w(TAG, "migrateDesktopDatabase: postKey failed $pragma: ${e.message}")
                                    }
                                }
                            }
                        }
                        
                        cipherDb = net.zetetic.database.sqlcipher.SQLiteDatabase.openDatabase(
                            sourceDb.absolutePath,
                            keyToUse,
                            null,
                            net.zetetic.database.sqlcipher.SQLiteDatabase.OPEN_READONLY,
                            null,
                            hook
                        )
                        Log.i(TAG, "migrateDesktopDatabase: Successfully opened with config '$configName'")
                        break
                    } catch (e: Exception) {
                        Log.w(TAG, "migrateDesktopDatabase: Config '$configName' failed: ${e.message}")
                        lastError = e
                    }
                }
                
                if (cipherDb == null) {
                    throw lastError ?: Exception("Failed to open encrypted database with any configuration")
                }
                
                // Migrate data using Room DAO directly
                migrateFromSQLCipher(cipherDb, targetDb, channelId)
                return
            } else {
                // Regular SQLite database
                Log.i(TAG, "migrateDesktopDatabase: Opening unencrypted database")
                sourceConn = android.database.sqlite.SQLiteDatabase.openDatabase(
                    sourceDb.absolutePath,
                    null,
                    android.database.sqlite.SQLiteDatabase.OPEN_READONLY
                )
            }
            
            // Create target (Android) database with Room schema
            val targetConn = android.database.sqlite.SQLiteDatabase.openOrCreateDatabase(
                targetDb.absolutePath,
                null
            )
            
            // Create Room tables
            targetConn.execSQL("""
                CREATE TABLE IF NOT EXISTS cloud_files (
                    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    telegram_message_id INTEGER NOT NULL,
                    file_id TEXT NOT NULL,
                    file_unique_id TEXT,
                    file_name TEXT NOT NULL,
                    mime_type TEXT,
                    size_bytes INTEGER NOT NULL,
                    uploaded_at INTEGER NOT NULL,
                    caption TEXT,
                    share_link TEXT,
                    checksum TEXT,
                    uploader_tokens TEXT DEFAULT ''
                )
            """.trimIndent())
            
            // Create upload_tasks table with all columns from version 5 (includes migration 4_5 columns)
            targetConn.execSQL("""
                CREATE TABLE IF NOT EXISTS upload_tasks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    uri TEXT NOT NULL,
                    display_name TEXT NOT NULL,
                    size_bytes INTEGER NOT NULL,
                    status TEXT NOT NULL,
                    progress INTEGER NOT NULL,
                    error TEXT,
                    created_at INTEGER NOT NULL,
                    file_id TEXT DEFAULT NULL,
                    completed_chunks_json TEXT DEFAULT NULL,
                    token_offset INTEGER NOT NULL DEFAULT 0
                )
            """.trimIndent())
            
            // Create download_tasks table with all columns from version 5 (includes migration 4_5 columns)
            targetConn.execSQL("""
                CREATE TABLE IF NOT EXISTS download_tasks (
                    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    file_id TEXT NOT NULL,
                    target_path TEXT NOT NULL,
                    status TEXT NOT NULL,
                    progress INTEGER NOT NULL,
                    error TEXT,
                    created_at INTEGER NOT NULL,
                    completed_chunks_json TEXT DEFAULT NULL,
                    chunk_file_ids TEXT DEFAULT NULL,
                    temp_chunk_dir TEXT DEFAULT NULL,
                    total_chunks INTEGER NOT NULL DEFAULT 0
                )
            """.trimIndent())
            
            // Create gallery_media table with all columns from version 5 (includes migrations 2_3 and 3_4)
            targetConn.execSQL("""
                CREATE TABLE IF NOT EXISTS gallery_media (
                    id INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL,
                    local_path TEXT NOT NULL,
                    filename TEXT NOT NULL,
                    mime_type TEXT NOT NULL,
                    size_bytes INTEGER NOT NULL,
                    date_taken INTEGER NOT NULL,
                    date_modified INTEGER NOT NULL,
                    width INTEGER NOT NULL DEFAULT 0,
                    height INTEGER NOT NULL DEFAULT 0,
                    duration_ms INTEGER NOT NULL DEFAULT 0,
                    thumbnail_path TEXT,
                    is_synced INTEGER NOT NULL DEFAULT 0,
                    telegram_file_id TEXT,
                    telegram_message_id INTEGER,
                    telegram_file_unique_id TEXT,
                    telegram_uploader_tokens TEXT,
                    sync_error TEXT,
                    last_sync_attempt INTEGER NOT NULL DEFAULT 0
                )
            """.trimIndent())
            targetConn.execSQL("CREATE UNIQUE INDEX IF NOT EXISTS index_gallery_media_local_path ON gallery_media (local_path)")
            
            // Room metadata table
            targetConn.execSQL("""
                CREATE TABLE IF NOT EXISTS room_master_table (
                    id INTEGER PRIMARY KEY,
                    identity_hash TEXT
                )
            """.trimIndent())
            targetConn.execSQL("INSERT OR REPLACE INTO room_master_table (id, identity_hash) VALUES(42, 'placeholder')")
            
            // Set database version to 5 (current version) so Room knows migrations are already applied
            targetConn.execSQL("PRAGMA user_version = 5")
            Log.i(TAG, "migrateDesktopDatabase: Set user_version to 5")
            
            // Check what tables exist in source
            val tablesCursor = sourceConn.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table'", null
            )
            val tables = mutableListOf<String>()
            while (tablesCursor.moveToNext()) {
                tables.add(tablesCursor.getString(0))
            }
            tablesCursor.close()
            Log.i(TAG, "migrateDesktopDatabase: Source tables: $tables")
            
            var migratedCount = 0
            
            // Migrate from 'files' table (desktop format)
            if (tables.contains("files")) {
                val cursor = sourceConn.rawQuery(
                    "SELECT file_id, file_name, file_size, upload_date, mime_type, message_id, telegram_file_id FROM files",
                    null
                )
                
                Log.i(TAG, "migrateDesktopDatabase: Found ${cursor.count} files in desktop database")
                
                while (cursor.moveToNext()) {
                    val fileId = cursor.getString(0) ?: continue
                    val fileName = cursor.getString(1) ?: "unknown"
                    val fileSize = cursor.getLong(2)
                    val uploadDate = cursor.getString(3) ?: ""
                    val mimeType = cursor.getString(4)
                    val messageId = cursor.getLong(5)
                    val telegramFileId = cursor.getString(6) ?: fileId
                    
                    // Parse upload date to timestamp
                    val uploadedAt = try {
                        java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
                            .parse(uploadDate)?.time ?: System.currentTimeMillis()
                    } catch (e: Exception) {
                        System.currentTimeMillis()
                    }
                    
                    // Build share link
                    val shareLink = if (channelId.startsWith("-100") && messageId > 0) {
                        val internalId = channelId.removePrefix("-100")
                        "https://t.me/c/$internalId/$messageId"
                    } else null
                    
                    targetConn.execSQL(
                        """INSERT INTO cloud_files 
                           (telegram_message_id, file_id, file_unique_id, file_name, mime_type, size_bytes, uploaded_at, caption, share_link, checksum)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                        arrayOf(messageId, telegramFileId, fileId, fileName, mimeType, fileSize, uploadedAt, null, shareLink, null)
                    )
                    migratedCount++
                }
                cursor.close()
            }
            
            // Also check for chunked_files table
            if (tables.contains("chunked_files")) {
                val cursor = sourceConn.rawQuery(
                    "SELECT file_id, original_filename, mime_type, total_size, total_chunks, created_at, status FROM chunked_files WHERE status = 'completed'",
                    null
                )
                
                Log.i(TAG, "migrateDesktopDatabase: Found ${cursor.count} chunked files")
                
                while (cursor.moveToNext()) {
                    val fileId = cursor.getString(0) ?: continue
                    val fileName = cursor.getString(1) ?: "unknown"
                    val mimeType = cursor.getString(2)
                    val totalSize = cursor.getLong(3)
                    val totalChunks = cursor.getInt(4)
                    val createdAt = cursor.getString(5) ?: ""
                    
                    val uploadedAt = try {
                        java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
                            .parse(createdAt)?.time ?: System.currentTimeMillis()
                    } catch (e: Exception) {
                        System.currentTimeMillis()
                    }
                    
                    // Get chunk message IDs
                    val chunksCursor = sourceConn.rawQuery(
                        "SELECT message_id, telegram_file_id FROM file_chunks WHERE file_id = ? ORDER BY chunk_number",
                        arrayOf(fileId)
                    )
                    val messageIds = mutableListOf<Long>()
                    val telegramFileIds = mutableListOf<String>()
                    while (chunksCursor.moveToNext()) {
                        messageIds.add(chunksCursor.getLong(0))
                        telegramFileIds.add(chunksCursor.getString(1) ?: "")
                    }
                    chunksCursor.close()
                    
                    val firstMessageId = messageIds.firstOrNull() ?: 0L
                    val shareLink = if (channelId.startsWith("-100") && firstMessageId > 0) {
                        val internalId = channelId.removePrefix("-100")
                        "https://t.me/c/$internalId/$firstMessageId"
                    } else null
                    
                    val caption = "[CHUNKED:$totalChunks|${messageIds.joinToString(",")}]"
                    val fileUniqueId = telegramFileIds.joinToString(",")
                    
                    targetConn.execSQL(
                        """INSERT INTO cloud_files 
                           (telegram_message_id, file_id, file_unique_id, file_name, mime_type, size_bytes, uploaded_at, caption, share_link, checksum)
                           VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                        arrayOf(firstMessageId, fileId, fileUniqueId, fileName, mimeType, totalSize, uploadedAt, caption, shareLink, null)
                    )
                    migratedCount++
                }
                cursor.close()
            }
            
            sourceConn.close()
            targetConn.close()
            
            Log.i(TAG, "migrateDesktopDatabase: Migration complete. Migrated $migratedCount files")
            
        } catch (e: Exception) {
            Log.e(TAG, "migrateDesktopDatabase: Error during migration", e)
            // If migration fails, just copy the file and hope Room can handle it
            sourceDb.copyTo(targetDb, overwrite = true)
        }
    }
    
    /**
     * Migrates data from an encrypted Android backup database to Room.
     * Assumes source database already has Android Room schema (cloud_files, upload_tasks, etc.).
     */
    private suspend fun migrateFromAndroidBackup(
        sourceConn: net.zetetic.database.sqlcipher.SQLiteDatabase
    ) = withContext(Dispatchers.IO) {
        Log.i(TAG, "migrateFromAndroidBackup: Starting Android backup migration")
        
        try {
            // Check what tables exist in source
            val tablesCursor = sourceConn.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' AND name != 'room_master_table'",
                null
            )
            val tables = mutableListOf<String>()
            while (tablesCursor.moveToNext()) {
                tables.add(tablesCursor.getString(0))
            }
            tablesCursor.close()
            Log.i(TAG, "migrateFromAndroidBackup: Source tables: $tables")
            
            var migratedCount = 0
            
            // Migrate cloud_files table
            if (tables.contains("cloud_files")) {
                val cursor = sourceConn.rawQuery(
                    "SELECT id, telegram_message_id, file_id, file_unique_id, file_name, mime_type, size_bytes, uploaded_at, caption, share_link, checksum, uploader_tokens FROM cloud_files",
                    null
                )
                
                Log.i(TAG, "migrateFromAndroidBackup: Found ${cursor.count} files in Android backup")
                
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    val telegramMessageId = cursor.getLong(1)
                    val fileId = cursor.getString(2) ?: continue
                    val fileUniqueId = cursor.getString(3)
                    val fileName = cursor.getString(4) ?: "unknown"
                    val mimeType = cursor.getString(5)
                    val sizeBytes = cursor.getLong(6)
                    val uploadedAt = cursor.getLong(7)
                    val caption = cursor.getString(8)
                    val shareLink = cursor.getString(9)
                    val checksum = cursor.getString(10)
                    val uploaderTokens = cursor.getString(11)
                    
                    // Insert using Room DAO
                    database.cloudFileDao().insert(
                        com.telegram.cloud.data.local.CloudFileEntity(
                            id = id,
                            telegramMessageId = telegramMessageId,
                            fileId = fileId,
                            fileUniqueId = fileUniqueId,
                            fileName = fileName,
                            mimeType = mimeType,
                            sizeBytes = sizeBytes,
                            uploadedAt = uploadedAt,
                            caption = caption,
                            shareLink = shareLink,
                            checksum = checksum,
                            uploaderTokens = uploaderTokens
                        )
                    )
                    migratedCount++
                }
                cursor.close()
            }
            
            // Migrate upload_tasks table
            if (tables.contains("upload_tasks")) {
                val cursor = sourceConn.rawQuery(
                    "SELECT id, uri, display_name, size_bytes, status, progress, error, created_at, file_id, completed_chunks_json, token_offset FROM upload_tasks",
                    null
                )
                
                Log.i(TAG, "migrateFromAndroidBackup: Found ${cursor.count} upload tasks")
                
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    val uri = cursor.getString(1) ?: continue
                    val displayName = cursor.getString(2) ?: "unknown"
                    val sizeBytes = cursor.getLong(3)
                    val statusStr = cursor.getString(4) ?: "QUEUED"
                    val progress = cursor.getInt(5)
                    val error = cursor.getString(6)
                    val createdAt = cursor.getLong(7)
                    val fileId = cursor.getString(8)
                    val completedChunksJson = cursor.getString(9)
                    val tokenOffset = cursor.getInt(10)
                    
                    val status = try {
                        com.telegram.cloud.data.local.UploadStatus.valueOf(statusStr)
                    } catch (e: Exception) {
                        com.telegram.cloud.data.local.UploadStatus.QUEUED
                    }
                    
                    database.uploadTaskDao().upsert(
                        com.telegram.cloud.data.local.UploadTaskEntity(
                            id = id,
                            uri = uri,
                            displayName = displayName,
                            sizeBytes = sizeBytes,
                            status = status,
                            progress = progress,
                            error = error,
                            createdAt = createdAt,
                            fileId = fileId,
                            completedChunksJson = completedChunksJson,
                            tokenOffset = tokenOffset
                        )
                    )
                }
                cursor.close()
            }
            
            // Migrate download_tasks table
            if (tables.contains("download_tasks")) {
                val cursor = sourceConn.rawQuery(
                    "SELECT id, file_id, target_path, status, progress, error, created_at, completed_chunks_json, chunk_file_ids, temp_chunk_dir, total_chunks FROM download_tasks",
                    null
                )
                
                Log.i(TAG, "migrateFromAndroidBackup: Found ${cursor.count} download tasks")
                
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    val fileId = cursor.getString(1) ?: continue
                    val targetPath = cursor.getString(2) ?: continue
                    val statusStr = cursor.getString(3) ?: "QUEUED"
                    val progress = cursor.getInt(4)
                    val error = cursor.getString(5)
                    val createdAt = cursor.getLong(6)
                    val completedChunksJson = cursor.getString(7)
                    val chunkFileIds = cursor.getString(8)
                    val tempChunkDir = cursor.getString(9)
                    val totalChunks = cursor.getInt(10)
                    
                    val status = try {
                        com.telegram.cloud.data.local.DownloadStatus.valueOf(statusStr)
                    } catch (e: Exception) {
                        com.telegram.cloud.data.local.DownloadStatus.QUEUED
                    }
                    
                    database.downloadTaskDao().upsert(
                        com.telegram.cloud.data.local.DownloadTaskEntity(
                            id = id,
                            fileId = fileId,
                            targetPath = targetPath,
                            status = status,
                            progress = progress,
                            error = error,
                            createdAt = createdAt,
                            completedChunksJson = completedChunksJson,
                            chunkFileIds = chunkFileIds,
                            tempChunkDir = tempChunkDir,
                            totalChunks = totalChunks
                        )
                    )
                }
                cursor.close()
            }
            
            // Migrate gallery_media table if it exists
            if (tables.contains("gallery_media")) {
                val cursor = sourceConn.rawQuery(
                    "SELECT id, local_path, filename, mime_type, size_bytes, date_taken, date_modified, width, height, duration_ms, thumbnail_path, is_synced, telegram_file_id, telegram_message_id, telegram_file_unique_id, telegram_uploader_tokens, sync_error, last_sync_attempt FROM gallery_media",
                    null
                )
                
                Log.i(TAG, "migrateFromAndroidBackup: Found ${cursor.count} gallery media items")
                
                while (cursor.moveToNext()) {
                    val id = cursor.getLong(0)
                    val localPath = cursor.getString(1) ?: continue
                    val filename = cursor.getString(2) ?: "unknown"
                    val mimeType = cursor.getString(3) ?: "application/octet-stream"
                    val sizeBytes = cursor.getLong(4)
                    val dateTaken = cursor.getLong(5)
                    val dateModified = cursor.getLong(6)
                    val width = cursor.getInt(7)
                    val height = cursor.getInt(8)
                    val durationMs = cursor.getLong(9)
                    val thumbnailPath = cursor.getString(10)
                    val isSynced = cursor.getInt(11) != 0
                    val telegramFileId = cursor.getString(12)
                    val telegramMessageIdLong = cursor.getLong(13)
                    val telegramFileUniqueId = cursor.getString(14)
                    val telegramUploaderTokens = cursor.getString(15)
                    val syncError = cursor.getString(16)
                    val lastSyncAttempt = cursor.getLong(17)
                    
                    val telegramMessageId = if (telegramMessageIdLong > 0) telegramMessageIdLong.toInt() else null
                    
                    database.galleryMediaDao().insert(
                        com.telegram.cloud.gallery.GalleryMediaEntity(
                            id = id,
                            localPath = localPath,
                            filename = filename,
                            mimeType = mimeType,
                            sizeBytes = sizeBytes,
                            dateTaken = dateTaken,
                            dateModified = dateModified,
                            width = width,
                            height = height,
                            durationMs = durationMs,
                            thumbnailPath = thumbnailPath,
                            isSynced = isSynced,
                            telegramFileId = telegramFileId,
                            telegramMessageId = telegramMessageId,
                            telegramFileUniqueId = telegramFileUniqueId,
                            telegramUploaderTokens = telegramUploaderTokens,
                            syncError = syncError,
                            lastSyncAttempt = lastSyncAttempt
                        )
                    )
                }
                cursor.close()
            }
            
            Log.i(TAG, "migrateFromAndroidBackup: Migration complete. Migrated $migratedCount files")
        } catch (e: Exception) {
            Log.e(TAG, "migrateFromAndroidBackup: Error during migration", e)
            throw e
        }
    }

    /**
     * Migrates from SQLCipher encrypted database to Android Room format.
     * Uses Room DAO directly to ensure data is visible immediately.
     */
    private suspend fun migrateFromSQLCipher(
        sourceConn: net.zetetic.database.sqlcipher.SQLiteDatabase,
        targetDb: File,
        channelId: String
    ) {
        // targetDb parameter kept for API compatibility but not used (migration uses Room DAO directly)
        Log.i(TAG, "migrateFromSQLCipher: Starting migration")
        
        try {
            // Clear existing Room data first (all tables)
            database.cloudFileDao().clear()
            database.uploadTaskDao().clear()
            database.downloadTaskDao().clear()
            Log.i(TAG, "migrateFromSQLCipher: Cleared existing Room data")
            
            // Check what tables exist in source
            val tablesCursor = sourceConn.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table'", null
            )
            val tables = mutableListOf<String>()
            while (tablesCursor.moveToNext()) {
                tables.add(tablesCursor.getString(0))
            }
            tablesCursor.close()
            Log.i(TAG, "migrateFromSQLCipher: Source tables: $tables")
            
            var migratedCount = 0
            
            // First, get list of chunked file names to exclude from 'files' table
            // (chunked files in desktop have same name in both tables)
            val chunkedFileNames = mutableSetOf<String>()
            if (tables.contains("chunked_files")) {
                val chunkedCursor = sourceConn.rawQuery(
                    "SELECT original_filename FROM chunked_files WHERE status = 'completed'", null
                )
                while (chunkedCursor.moveToNext()) {
                    chunkedCursor.getString(0)?.let { chunkedFileNames.add(it) }
                }
                chunkedCursor.close()
                Log.i(TAG, "migrateFromSQLCipher: Found ${chunkedFileNames.size} chunked file names to exclude: $chunkedFileNames")
            }
            
            // Migrate from 'files' table (desktop format) - exclude files that are also in chunked_files
            if (tables.contains("files")) {
                val cursor = sourceConn.rawQuery(
                    "SELECT file_id, file_name, file_size, upload_date, mime_type, message_id, telegram_file_id, uploader_bot_token FROM files",
                    null
                )
                
                Log.i(TAG, "migrateFromSQLCipher: Found ${cursor.count} files in desktop database")
                
                while (cursor.moveToNext()) {
                    val fileId = cursor.getString(0) ?: continue
                    val fileName = cursor.getString(1) ?: "unknown"
                    
                    // Skip if this file is also in chunked_files (will be migrated from there with chunk info)
                    if (chunkedFileNames.contains(fileName)) {
                        Log.d(TAG, "migrateFromSQLCipher: Skipping '$fileName' (is chunked file)")
                        continue
                    }
                    
                    val fileSize = cursor.getLong(2)
                    val uploadDate = cursor.getString(3) ?: ""
                    val mimeType = cursor.getString(4)
                    val messageId = cursor.getLong(5)
                    val telegramFileId = cursor.getString(6) ?: fileId
                    val uploaderToken = cursor.getString(7) ?: ""
                    
                    // Parse upload date to timestamp
                    val uploadedAt = try {
                        java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
                            .parse(uploadDate)?.time ?: System.currentTimeMillis()
                    } catch (e: Exception) {
                        System.currentTimeMillis()
                    }
                    
                    // Build share link
                    val shareLink = if (channelId.startsWith("-100") && messageId > 0) {
                        val internalId = channelId.removePrefix("-100")
                        "https://t.me/c/$internalId/$messageId"
                    } else null
                    
                    // Insert using Room DAO
                    database.cloudFileDao().insert(
                        com.telegram.cloud.data.local.CloudFileEntity(
                            telegramMessageId = messageId,
                            fileId = telegramFileId,
                            fileUniqueId = fileId,
                            fileName = fileName,
                            mimeType = mimeType,
                            sizeBytes = fileSize,
                            uploadedAt = uploadedAt,
                            caption = null,
                            shareLink = shareLink,
                            checksum = null,
                            uploaderTokens = uploaderToken
                        )
                    )
                    migratedCount++
                    Log.d(TAG, "migrateFromSQLCipher: Migrated file: $fileName")
                }
                cursor.close()
            }
            
            // Migrate chunked_files table
            if (tables.contains("chunked_files")) {
                // Desktop schema: file_id, original_filename, mime_type, total_size, total_chunks, 
                // completed_chunks, upload_started, status, last_update, original_file_hash, final_telegram_file_id
                val cursor = sourceConn.rawQuery(
                    "SELECT file_id, original_filename, mime_type, total_size, total_chunks, upload_started, status FROM chunked_files WHERE status = 'completed'",
                    null
                )
                
                Log.i(TAG, "migrateFromSQLCipher: Found ${cursor.count} chunked files")
                
                while (cursor.moveToNext()) {
                    val fileId = cursor.getString(0) ?: continue
                    val fileName = cursor.getString(1) ?: "unknown"
                    val mimeType = cursor.getString(2)
                    val totalSize = cursor.getLong(3)
                    val totalChunks = cursor.getInt(4)
                    val uploadStarted = cursor.getString(5) ?: ""
                    
                    val uploadedAt = try {
                        java.text.SimpleDateFormat("yyyy-MM-dd HH:mm:ss", java.util.Locale.US)
                            .parse(uploadStarted)?.time ?: System.currentTimeMillis()
                    } catch (e: Exception) {
                        System.currentTimeMillis()
                    }
                    
                    // Get chunk message IDs and uploader tokens
                    val chunksCursor = sourceConn.rawQuery(
                        "SELECT message_id, telegram_file_id, uploader_bot_token FROM file_chunks WHERE file_id = ? ORDER BY chunk_number",
                        arrayOf(fileId)
                    )
                    val messageIds = mutableListOf<Long>()
                    val telegramFileIds = mutableListOf<String>()
                    val uploaderTokens = mutableListOf<String>()
                    while (chunksCursor.moveToNext()) {
                        messageIds.add(chunksCursor.getLong(0))
                        telegramFileIds.add(chunksCursor.getString(1) ?: "")
                        uploaderTokens.add(chunksCursor.getString(2) ?: "")
                    }
                    chunksCursor.close()
                    
                    val firstMessageId = messageIds.firstOrNull() ?: 0L
                    val shareLink = if (channelId.startsWith("-100") && firstMessageId > 0) {
                        val internalId = channelId.removePrefix("-100")
                        "https://t.me/c/$internalId/$firstMessageId"
                    } else null
                    
                    val caption = "[CHUNKED:$totalChunks|${messageIds.joinToString(",")}]"
                    val fileUniqueId = telegramFileIds.joinToString(",")
                    val uploaderTokensStr = uploaderTokens.joinToString(",")
                    
                    // Insert using Room DAO
                    database.cloudFileDao().insert(
                        com.telegram.cloud.data.local.CloudFileEntity(
                            telegramMessageId = firstMessageId,
                            fileId = fileId,
                            fileUniqueId = fileUniqueId,
                            fileName = fileName,
                            mimeType = mimeType,
                            sizeBytes = totalSize,
                            uploadedAt = uploadedAt,
                            caption = caption,
                            shareLink = shareLink,
                            checksum = null,
                            uploaderTokens = uploaderTokensStr
                        )
                    )
                    migratedCount++
                    Log.d(TAG, "migrateFromSQLCipher: Migrated chunked file: $fileName with ${uploaderTokens.size} tokens")
                }
                cursor.close()
            }
            
            sourceConn.close()
            
            Log.i(TAG, "migrateFromSQLCipher: Migration complete. Migrated $migratedCount files")
            
        } catch (e: Exception) {
            Log.e(TAG, "migrateFromSQLCipher: Error during migration", e)
            throw e
        }
    }

    private fun buildEnvFile(config: BotConfig): String {
        val builder = StringBuilder()
        if (config.tokens.isNotEmpty()) {
            builder.append("BOT_TOKEN=").append(config.tokens.first()).append("\n")
            config.tokens.forEachIndexed { index, token ->
                builder.append("BOT_TOKEN_").append(index + 1).append("=").append(token).append("\n")
            }
        }
        builder.append("CHANNEL_ID=").append(config.channelId).append("\n")
        config.chatId?.takeIf { it.isNotBlank() }?.let {
            builder.append("CHAT_ID=").append(it).append("\n")
        }
        return builder.toString()
    }

    private fun parseEnv(content: String): Map<String, String> {
        // Check if content is in EnvManager encrypted format: IV(base64)|HASH(hex)|CIPHERTEXT(base64)
        // Format has exactly 2 pipe separators and the second part is a 64-char hex hash
        val parts = content.trim().split("|")
        val isEnvManagerFormat = parts.size == 3 && 
            parts[1].length == 64 && 
            parts[1].all { it.isDigit() || it in 'a'..'f' }
        
        Log.i(TAG, "parseEnv: parts=${parts.size}, isEnvManagerFormat=$isEnvManagerFormat")
        
        if (isEnvManagerFormat) {
            Log.i(TAG, "parseEnv: Detected EnvManager encrypted format, decrypting...")
            val decrypted = decryptEnvManagerFormat(content.trim())
            if (decrypted != null) {
                Log.i(TAG, "parseEnv: EnvManager decryption successful")
                return parseEnvPlaintext(decrypted)
            } else {
                Log.e(TAG, "parseEnv: EnvManager decryption failed, trying as plaintext")
            }
        }
        
        return parseEnvPlaintext(content)
    }
    
    private fun parseEnvPlaintext(content: String): Map<String, String> =
        content.lineSequence()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") && it.contains("=") }
            .associate {
                val idx = it.indexOf("=")
                val key = it.substring(0, idx).trim()
                val value = it.substring(idx + 1).trim()
                key to value
            }
    
    /**
     * Decrypts content in EnvManager format: IV(base64)|CONTENT_HASH(hex)|CIPHERTEXT(base64)
     * The key is derived using PBKDF2 with the content hash as password and fixed salt.
     */
    private fun decryptEnvManagerFormat(content: String): String? {
        try {
            val parts = content.split("|")
            if (parts.size != 3) {
                Log.e(TAG, "decryptEnvManagerFormat: Expected 3 parts, got ${parts.size}")
                return null
            }
            
            val ivBase64 = parts[0]
            val contentHash = parts[1]  // This is the hex hash used to derive the key
            val ciphertextBase64 = parts[2]
            
            Log.i(TAG, "decryptEnvManagerFormat: ivBase64=${ivBase64.take(20)}...")
            Log.i(TAG, "decryptEnvManagerFormat: contentHash=${contentHash.take(20)}... (${contentHash.length} chars)")
            Log.i(TAG, "decryptEnvManagerFormat: ciphertextBase64=${ciphertextBase64.take(20)}... (${ciphertextBase64.length} chars)")
            
            // Decode IV and ciphertext from Base64
            val iv = Base64.decode(ivBase64, Base64.NO_WRAP)
            val ciphertext = Base64.decode(ciphertextBase64, Base64.NO_WRAP)
            
            Log.i(TAG, "decryptEnvManagerFormat: iv=${iv.size}B, ciphertext=${ciphertext.size}B")
            
            if (iv.size != 16) {
                Log.e(TAG, "decryptEnvManagerFormat: Invalid IV size: ${iv.size}")
                return null
            }
            
            // Derive key using PBKDF2 with contentHash as password
            val key = deriveEnvManagerKey(contentHash)
            Log.i(TAG, "decryptEnvManagerFormat: Key derived, ${key.size} bytes")
            
            // Decrypt using AES-256-CBC
            val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
            cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
            
            val decrypted = cipher.doFinal(ciphertext)
            val result = String(decrypted, Charsets.UTF_8)
            
            Log.i(TAG, "decryptEnvManagerFormat: Decrypted ${decrypted.size} bytes")
            Log.i(TAG, "decryptEnvManagerFormat: First 200 chars: ${result.take(200)}")
            
            return result
            
        } catch (e: Exception) {
            Log.e(TAG, "decryptEnvManagerFormat: Failed", e)
            return null
        }
    }
    
    /**
     * Derives a 256-bit key using PBKDF2-HMAC-SHA256.
     * This matches the desktop EnvManager implementation.
     */
    private fun deriveEnvManagerKey(password: String): ByteArray {
        val salt = ENVMANAGER_SALT.toByteArray(Charsets.UTF_8)
        
        val factory = SecretKeyFactory.getInstance("PBKDF2WithHmacSHA256")
        val spec = PBEKeySpec(password.toCharArray(), salt, ENVMANAGER_PBKDF2_ITERATIONS, 256)
        val secretKey = factory.generateSecret(spec)
        
        return secretKey.encoded
    }

    private fun encryptFile(input: File, output: File, password: String) {
        val plain = input.readBytes()
        val encrypted = encryptBytes(plain, password)
        output.parentFile?.mkdirs()
        output.writeBytes(encrypted)
    }

    private fun decryptFile(input: File, password: String): ByteArray {
        val bytes = input.readBytes()
        return decryptBytes(bytes, password)
    }

    private fun encryptBytes(plain: ByteArray, password: String): ByteArray {
        val salt = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val iv = ByteArray(16).also { SecureRandom().nextBytes(it) }
        val key = deriveKey(password, salt)
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.ENCRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        val cipherText = cipher.doFinal(plain)
        val magic = "BKP1".toByteArray()
        return ByteArray(magic.size + salt.size + iv.size + cipherText.size).apply {
            var pos = 0
            magic.copyInto(this, pos); pos += magic.size
            salt.copyInto(this, pos); pos += salt.size
            iv.copyInto(this, pos); pos += iv.size
            cipherText.copyInto(this, pos)
        }
    }

    private fun decryptBytes(encoded: ByteArray, password: String): ByteArray {
        Log.i(TAG, "decryptBytes: encoded size=${encoded.size}, password length=${password.length}")
        
        val magic = if (encoded.size >= 4) String(encoded, 0, 4) else ""
        Log.i(TAG, "decryptBytes: magic='$magic'")
        
        require(encoded.size >= 36 && magic == "BKP1") { 
            "Backup cifrado inválido: size=${encoded.size}, magic='$magic'"
        }
        
        val salt = encoded.copyOfRange(4, 20)
        val iv = encoded.copyOfRange(20, 36)
        val cipherData = encoded.copyOfRange(36, encoded.size)
        
        Log.i(TAG, "decryptBytes: salt=${salt.size}B, iv=${iv.size}B, cipherData=${cipherData.size}B")
        
        val key = deriveKey(password, salt)
        Log.i(TAG, "decryptBytes: key derived, length=${key.size}")
        
        val cipher = Cipher.getInstance("AES/CBC/PKCS5Padding")
        cipher.init(Cipher.DECRYPT_MODE, SecretKeySpec(key, "AES"), IvParameterSpec(iv))
        
        try {
            val decrypted = cipher.doFinal(cipherData)
            Log.i(TAG, "decryptBytes: decrypted ${decrypted.size} bytes")
            return decrypted
        } catch (e: Exception) {
            Log.e(TAG, "decryptBytes: Decryption failed - wrong password?", e)
            throw e
        }
    }

    private fun deriveKey(password: String, salt: ByteArray): ByteArray {
        val digest = MessageDigest.getInstance("SHA-256")
        digest.update(password.toByteArray())
        digest.update(salt)
        return digest.digest()
    }

    private fun zipDirectory(sourceDir: File, target: File) {
        target.parentFile?.mkdirs()
        ZipOutputStream(FileOutputStream(target)).use { zos ->
            val basePath = sourceDir.absolutePath.length + 1
            sourceDir.walkTopDown().filter { it.isFile }.forEach { file ->
                val entryName = file.absolutePath.substring(basePath).replace("\\", "/")
                zos.putNextEntry(ZipEntry(entryName))
                file.inputStream().use { it.copyTo(zos) }
                zos.closeEntry()
            }
        }
    }

    private fun unzip(zipFile: File, destDir: File) {
        ZipInputStream(FileInputStream(zipFile)).use { zis ->
            var entry = zis.nextEntry
            while (entry != null) {
                val outFile = File(destDir, entry.name)
                if (entry.isDirectory) {
                    outFile.mkdirs()
                } else {
                    outFile.parentFile?.mkdirs()
                    FileOutputStream(outFile).use { zis.copyTo(it) }
                }
                zis.closeEntry()
                entry = zis.nextEntry
            }
        }
    }

    suspend fun requiresPassword(file: File): Boolean = withContext(Dispatchers.IO) {
        ZipInputStream(FileInputStream(file)).use { zis ->
            var entry = zis.nextEntry
            var fallbackEncrypted = false
            while (entry != null) {
                when (entry.name) {
                    "backup_manifest.json" -> {
                        val text = zis.bufferedReader().use { it.readText() }
                        return@withContext JSONObject(text).optBoolean("encrypted", false)
                    }
                    ".env.enc", "telegram_cloud.db.enc" -> fallbackEncrypted = true
                }
                entry = zis.nextEntry
            }
            fallbackEncrypted
        }
    }
}

