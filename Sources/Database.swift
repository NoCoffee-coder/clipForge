import Foundation
import SQLite3

// MARK: - SQLite Wrapper

/// Thin wrapper over the SQLite3 C API, mirroring the Rust Database struct.
/// Thread-safe via a serial queue.
final class Database {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "com.clipforge.db")

    /// SQLITE_TRANSIENT equivalent — tells SQLite to copy the string data
    private static let transientDestructor: (@convention(c) (UnsafeMutableRawPointer?) -> Void)? =
        unsafeBitCast(-1, to: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)

    init(path: String) {
        if sqlite3_open(path, &db) != SQLITE_OK {
            fatalError("Unable to open database at \(path)")
        }
        configure()
        migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: Configuration

    private func configure() {
        exec("PRAGMA journal_mode = WAL;")
        exec("PRAGMA synchronous = NORMAL;")
        exec("PRAGMA temp_store = MEMORY;")
        exec("PRAGMA cache_size = -8000;")
    }

    // MARK: Schema

    private func migrate() {
        let sql = """
        CREATE TABLE IF NOT EXISTS clipboard_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            content TEXT,
            image_path TEXT,
            file_paths TEXT,
            preview TEXT,
            source_app TEXT,
            is_pinned INTEGER NOT NULL DEFAULT 0,
            is_sensitive INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL,
            accessed_at INTEGER
        );
        CREATE INDEX IF NOT EXISTS idx_created_at ON clipboard_items(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_type ON clipboard_items(type);
        CREATE INDEX IF NOT EXISTS idx_pinned ON clipboard_items(is_pinned) WHERE is_pinned = 1;

        CREATE TABLE IF NOT EXISTS image_assets (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL UNIQUE,
            hash TEXT NOT NULL,
            width INTEGER,
            height INTEGER,
            byte_size INTEGER,
            created_at INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS html_temp_files (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            file_path TEXT NOT NULL UNIQUE,
            item_id INTEGER,
            created_at INTEGER NOT NULL,
            expires_at INTEGER NOT NULL
        );
        CREATE INDEX IF NOT EXISTS idx_expires_at ON html_temp_files(expires_at);
        """
        exec(sql)
    }

    // MARK: Helpers

    @discardableResult
    private func exec(_ sql: String) -> Bool {
        sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK
    }

    private func now() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func rowToItem(_ stmt: OpaquePointer) -> ClipboardItem {
        let id = sqlite3_column_int64(stmt, 0)
        let type = String(cString: sqlite3_column_text(stmt, 1))
        let content = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
        let imagePath = sqlite3_column_text(stmt, 3).map { String(cString: $0) }
        let filePaths = sqlite3_column_text(stmt, 4).map { String(cString: $0) }
        let preview = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
        let sourceApp = sqlite3_column_text(stmt, 6).map { String(cString: $0) }
        let isPinned = sqlite3_column_int(stmt, 7) != 0
        let isSensitive = sqlite3_column_int(stmt, 8) != 0
        let createdAt = sqlite3_column_int64(stmt, 9)
        let accessedAt = sqlite3_column_type(stmt, 10) != SQLITE_NULL
            ? sqlite3_column_int64(stmt, 10) : nil

        return ClipboardItem(
            id: id, type: type, content: content,
            imagePath: imagePath, filePaths: filePaths,
            preview: preview, sourceApp: sourceApp,
            isPinned: isPinned, isSensitive: isSensitive,
            createdAt: createdAt, accessedAt: accessedAt
        )
    }

    private func bindTextNullable(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let v = value {
            sqlite3_bind_text(stmt, index, v, -1, Database.transientDestructor)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    // MARK: CRUD

    func insertItem(type: String, content: String?, imagePath: String?,
                    filePaths: String?, preview: String?, sourceApp: String?) -> Int64 {
        var result: Int64 = -1
        queue.sync {
            let sql = """
            INSERT INTO clipboard_items
                (type, content, image_path, file_paths, preview, source_app, is_sensitive, created_at)
            VALUES (?, ?, ?, ?, ?, ?, 0, ?)
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

            sqlite3_bind_text(stmt, 1, type, -1, Database.transientDestructor)
            bindTextNullable(stmt, 2, content)
            bindTextNullable(stmt, 3, imagePath)
            bindTextNullable(stmt, 4, filePaths)
            bindTextNullable(stmt, 5, preview)
            bindTextNullable(stmt, 6, sourceApp)
            sqlite3_bind_int64(stmt, 7, now())

            if sqlite3_step(stmt) == SQLITE_DONE {
                result = sqlite3_last_insert_rowid(db)
            }
            sqlite3_finalize(stmt)
        }
        return result
    }

    func getHistory(limit: Int = 200, offset: Int = 0) -> [ClipboardItem] {
        var result: [ClipboardItem] = []
        queue.sync {
            let sql = """
            SELECT id, type, content, image_path, file_paths, preview,
                   source_app, is_pinned, is_sensitive, created_at, accessed_at
            FROM clipboard_items
            ORDER BY is_pinned DESC, created_at DESC
            LIMIT ? OFFSET ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            sqlite3_bind_int(stmt, 2, Int32(offset))

            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(rowToItem(stmt!))
            }
            sqlite3_finalize(stmt)
        }
        return result
    }

    func search(query: String, typeFilter: String?, timeFrom: Int64?, limit: Int = 100) -> [ClipboardItem] {
        var result: [ClipboardItem] = []
        queue.sync {
            let sql = """
            SELECT id, type, content, image_path, file_paths, preview,
                   source_app, is_pinned, is_sensitive, created_at, accessed_at
            FROM clipboard_items
            WHERE (content LIKE ? OR preview LIKE ?)
              AND (? IS NULL OR type = ?)
              AND (? IS NULL OR created_at >= ?)
            ORDER BY is_pinned DESC, created_at DESC
            LIMIT ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }

            let pattern = "%\(query)%"
            sqlite3_bind_text(stmt, 1, pattern, -1, Database.transientDestructor)
            sqlite3_bind_text(stmt, 2, pattern, -1, Database.transientDestructor)
            bindTextNullable(stmt, 3, typeFilter)
            bindTextNullable(stmt, 4, typeFilter)

            if let tf = timeFrom { sqlite3_bind_int64(stmt, 5, tf) } else { sqlite3_bind_null(stmt, 5) }
            if let tf = timeFrom { sqlite3_bind_int64(stmt, 6, tf) } else { sqlite3_bind_null(stmt, 6) }

            sqlite3_bind_int(stmt, 7, Int32(limit))

            while sqlite3_step(stmt) == SQLITE_ROW {
                result.append(rowToItem(stmt!))
            }
            sqlite3_finalize(stmt)
        }
        return result
    }

    func getItem(id: Int64) -> ClipboardItem? {
        var result: ClipboardItem?
        queue.sync {
            let sql = """
            SELECT id, type, content, image_path, file_paths, preview,
                   source_app, is_pinned, is_sensitive, created_at, accessed_at
            FROM clipboard_items WHERE id = ?
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) == SQLITE_ROW {
                result = rowToItem(stmt!)
            }
            sqlite3_finalize(stmt)
        }
        return result
    }

    func deleteItem(id: Int64) {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM clipboard_items WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func togglePin(id: Int64) -> Bool {
        var pinned = false
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "UPDATE clipboard_items SET is_pinned = 1 - is_pinned WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)

            sqlite3_prepare_v2(db, "SELECT is_pinned FROM clipboard_items WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, id)
            if sqlite3_step(stmt) == SQLITE_ROW {
                pinned = sqlite3_column_int(stmt, 0) != 0
            }
            sqlite3_finalize(stmt)
        }
        return pinned
    }

    func touchItem(id: Int64) {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "UPDATE clipboard_items SET accessed_at = ? WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, now())
            sqlite3_bind_int64(stmt, 2, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func trimHistory(limit: Int) -> Int {
        var changes = 0
        queue.sync {
            let sql = """
            DELETE FROM clipboard_items
            WHERE id IN (
                SELECT id FROM clipboard_items
                WHERE is_pinned = 0
                ORDER BY created_at DESC
                LIMIT -1 OFFSET ?
            )
            """
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
            sqlite3_bind_int(stmt, 1, Int32(limit))
            sqlite3_step(stmt)
            changes = Int(sqlite3_changes(db))
            sqlite3_finalize(stmt)
        }
        return changes
    }

    func latestItemId() -> Int64? {
        var id: Int64?
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "SELECT id FROM clipboard_items ORDER BY created_at DESC LIMIT 1", -1, &stmt, nil)
            if sqlite3_step(stmt) == SQLITE_ROW {
                id = sqlite3_column_int64(stmt, 0)
            }
            sqlite3_finalize(stmt)
        }
        return id
    }

    // MARK: HTML temp files

    func registerHtmlFile(path: String, itemId: Int64?, ttlMs: Int64) {
        queue.sync {
            let expiresAt = ttlMs == 0 ? 0 : now() + ttlMs
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, """
                INSERT OR REPLACE INTO html_temp_files (file_path, item_id, created_at, expires_at)
                VALUES (?, ?, ?, ?)
            """, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, path, -1, Database.transientDestructor)
            if let iid = itemId { sqlite3_bind_int64(stmt, 2, iid) } else { sqlite3_bind_null(stmt, 2) }
            sqlite3_bind_int64(stmt, 3, now())
            sqlite3_bind_int64(stmt, 4, expiresAt)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    func getExpiredHtmlFiles() -> [HtmlTempFile] {
        var files: [HtmlTempFile] = []
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, """
                SELECT id, file_path, item_id, created_at, expires_at
                FROM html_temp_files WHERE expires_at > 0 AND expires_at < ?
            """, -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, now())
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let fp = String(cString: sqlite3_column_text(stmt, 1))
                let iid = sqlite3_column_type(stmt, 2) != SQLITE_NULL ? sqlite3_column_int64(stmt, 2) : nil
                let ca = sqlite3_column_int64(stmt, 3)
                let ea = sqlite3_column_int64(stmt, 4)
                files.append(HtmlTempFile(id: id, filePath: fp, itemId: iid, createdAt: ca, expiresAt: ea))
            }
            sqlite3_finalize(stmt)
        }
        return files
    }

    func removeHtmlFileRecord(id: Int64) {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM html_temp_files WHERE id = ?", -1, &stmt, nil)
            sqlite3_bind_int64(stmt, 1, id)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }

    // MARK: Image assets

    func registerImage(_ asset: ImageAsset) {
        queue.sync {
            var stmt: OpaquePointer?
            sqlite3_prepare_v2(db, """
                INSERT OR REPLACE INTO image_assets (file_path, hash, width, height, byte_size, created_at)
                VALUES (?, ?, ?, ?, ?, ?)
            """, -1, &stmt, nil)
            sqlite3_bind_text(stmt, 1, asset.filePath, -1, Database.transientDestructor)
            sqlite3_bind_text(stmt, 2, asset.hash, -1, Database.transientDestructor)
            if let w = asset.width { sqlite3_bind_int(stmt, 3, w) } else { sqlite3_bind_null(stmt, 3) }
            if let h = asset.height { sqlite3_bind_int(stmt, 4, h) } else { sqlite3_bind_null(stmt, 4) }
            if let bs = asset.byteSize { sqlite3_bind_int64(stmt, 5, bs) } else { sqlite3_bind_null(stmt, 5) }
            sqlite3_bind_int64(stmt, 6, asset.createdAt)
            sqlite3_step(stmt)
            sqlite3_finalize(stmt)
        }
    }
}
