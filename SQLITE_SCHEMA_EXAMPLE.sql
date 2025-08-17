-- ImageIntact SQLite Schema
-- Optimized for checksum manifest storage and file tracking

-- ============================================================================
-- PRAGMA Settings (run these after opening the database)
-- ============================================================================
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;
PRAGMA page_size = 8192;  -- Larger pages for blob data
PRAGMA cache_size = -64000;  -- 64MB cache
PRAGMA mmap_size = 268435456;  -- 256MB memory-mapped I/O
PRAGMA temp_store = MEMORY;
PRAGMA auto_vacuum = INCREMENTAL;

-- ============================================================================
-- Core Tables
-- ============================================================================

-- Manifest runs (each time you scan)
CREATE TABLE manifests (
    id INTEGER PRIMARY KEY,
    run_id TEXT UNIQUE NOT NULL,  -- UUID or timestamp-based ID
    created_at INTEGER NOT NULL,  -- Unix timestamp
    completed_at INTEGER,  -- NULL while running
    source_type TEXT NOT NULL,  -- 'local', 'nas', 'cloud', etc
    source_path TEXT NOT NULL,  -- Root path scanned
    source_host TEXT,  -- Hostname/IP if remote
    total_files INTEGER DEFAULT 0,
    total_bytes INTEGER DEFAULT 0,
    tool_version TEXT,  -- ImageIntact version
    metadata TEXT  -- JSON for extra data
);

CREATE INDEX idx_manifests_created ON manifests(created_at DESC);
CREATE INDEX idx_manifests_source ON manifests(source_type, source_path);

-- File entries (the main data)
CREATE TABLE entries (
    manifest_id INTEGER NOT NULL,
    path TEXT NOT NULL,  -- Relative to manifest source_path
    size INTEGER NOT NULL,
    mtime INTEGER NOT NULL,  -- Modification time (unix timestamp)
    ctime INTEGER,  -- Creation time if available
    is_directory INTEGER DEFAULT 0,  -- Boolean
    is_symlink INTEGER DEFAULT 0,
    file_type TEXT,  -- 'raw', 'jpeg', 'dng', 'xmp', 'video', etc
    
    -- Checksums stored as BLOB (binary) for space efficiency
    checksum_xxh64 BLOB,  -- 8 bytes
    checksum_sha256 BLOB,  -- 32 bytes
    checksum_blake3 BLOB,  -- 32 bytes (if you add it later)
    
    -- Quick lookup fields
    extension TEXT GENERATED ALWAYS AS (
        LOWER(SUBSTR(path, LENGTH(path) - LENGTH(REPLACE(path, '.', '')) + 1))
    ) STORED,
    
    PRIMARY KEY (manifest_id, path),
    FOREIGN KEY (manifest_id) REFERENCES manifests(id) ON DELETE CASCADE
) WITHOUT ROWID;

-- Indexes for common queries
CREATE INDEX idx_entries_checksum_xxh64 ON entries(checksum_xxh64) 
    WHERE checksum_xxh64 IS NOT NULL;
CREATE INDEX idx_entries_checksum_sha256 ON entries(checksum_sha256) 
    WHERE checksum_sha256 IS NOT NULL;
CREATE INDEX idx_entries_size_mtime ON entries(size, mtime);
CREATE INDEX idx_entries_extension ON entries(extension) 
    WHERE is_directory = 0;

-- ============================================================================
-- Deduplication & Change Tracking
-- ============================================================================

-- Unique content tracking (normalized across all manifests)
CREATE TABLE content (
    id INTEGER PRIMARY KEY,
    size INTEGER NOT NULL,
    checksum_xxh64 BLOB NOT NULL,
    checksum_sha256 BLOB,
    first_seen_manifest_id INTEGER NOT NULL,
    first_seen_at INTEGER NOT NULL,
    last_seen_manifest_id INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL,
    occurrence_count INTEGER DEFAULT 1,
    total_bytes_saved INTEGER DEFAULT 0,  -- (occurrence_count - 1) * size
    
    FOREIGN KEY (first_seen_manifest_id) REFERENCES manifests(id),
    FOREIGN KEY (last_seen_manifest_id) REFERENCES manifests(id),
    UNIQUE(checksum_xxh64, size)  -- Composite unique constraint
);

CREATE INDEX idx_content_checksums ON content(checksum_xxh64, checksum_sha256);
CREATE INDEX idx_content_savings ON content(total_bytes_saved DESC);

-- Path history (track the same logical file across runs)
CREATE TABLE path_history (
    id INTEGER PRIMARY KEY,
    path TEXT NOT NULL,
    first_manifest_id INTEGER NOT NULL,
    last_manifest_id INTEGER NOT NULL,
    change_count INTEGER DEFAULT 0,  -- How many times content changed
    last_size INTEGER,
    last_checksum_xxh64 BLOB,
    status TEXT,  -- 'stable', 'modified', 'deleted', 'new'
    
    FOREIGN KEY (first_manifest_id) REFERENCES manifests(id),
    FOREIGN KEY (last_manifest_id) REFERENCES manifests(id)
);

CREATE UNIQUE INDEX idx_path_history_path ON path_history(path);
CREATE INDEX idx_path_history_status ON path_history(status);

-- ============================================================================
-- Relationships & Groups
-- ============================================================================

-- File relationships (sidecar files, derivatives, etc)
CREATE TABLE relationships (
    primary_manifest_id INTEGER NOT NULL,
    primary_path TEXT NOT NULL,
    related_manifest_id INTEGER NOT NULL,
    related_path TEXT NOT NULL,
    relationship_type TEXT NOT NULL,  -- 'sidecar', 'derivative', 'version', etc
    confidence REAL DEFAULT 1.0,  -- 0.0 to 1.0
    created_at INTEGER NOT NULL,
    
    PRIMARY KEY (primary_manifest_id, primary_path, related_manifest_id, related_path),
    FOREIGN KEY (primary_manifest_id, primary_path) 
        REFERENCES entries(manifest_id, path) ON DELETE CASCADE,
    FOREIGN KEY (related_manifest_id, related_path) 
        REFERENCES entries(manifest_id, path) ON DELETE CASCADE
) WITHOUT ROWID;

CREATE INDEX idx_relationships_type ON relationships(relationship_type);

-- Logical groups (e.g., RAW+XMP+JPEG that belong together)
CREATE TABLE file_groups (
    id INTEGER PRIMARY KEY,
    group_type TEXT NOT NULL,  -- 'photo_set', 'video_project', etc
    primary_checksum_xxh64 BLOB,  -- The "main" file's checksum
    created_at INTEGER NOT NULL,
    metadata TEXT  -- JSON for additional info
);

CREATE TABLE file_group_members (
    group_id INTEGER NOT NULL,
    manifest_id INTEGER NOT NULL,
    path TEXT NOT NULL,
    role TEXT,  -- 'primary', 'sidecar', 'thumbnail', etc
    
    PRIMARY KEY (group_id, manifest_id, path),
    FOREIGN KEY (group_id) REFERENCES file_groups(id) ON DELETE CASCADE,
    FOREIGN KEY (manifest_id, path) REFERENCES entries(manifest_id, path)
) WITHOUT ROWID;

-- ============================================================================
-- Operations & Sync Tracking
-- ============================================================================

-- Track operations like copies, moves, verifications
CREATE TABLE operations (
    id INTEGER PRIMARY KEY,
    operation_type TEXT NOT NULL,  -- 'copy', 'verify', 'delete', 'restore'
    started_at INTEGER NOT NULL,
    completed_at INTEGER,
    source_manifest_id INTEGER,
    source_path TEXT,
    dest_path TEXT,
    size INTEGER,
    checksum_xxh64 BLOB,
    status TEXT,  -- 'pending', 'running', 'completed', 'failed'
    error_message TEXT,
    metadata TEXT,  -- JSON for operation-specific data
    
    FOREIGN KEY (source_manifest_id) REFERENCES manifests(id)
);

CREATE INDEX idx_operations_status ON operations(status, started_at DESC);
CREATE INDEX idx_operations_checksum ON operations(checksum_xxh64) 
    WHERE checksum_xxh64 IS NOT NULL;

-- ============================================================================
-- Full-Text Search Support (Optional but useful)
-- ============================================================================

-- Virtual table for path searching
CREATE VIRTUAL TABLE entries_fts USING fts5(
    path,
    content=entries,
    content_rowid=rowid,
    tokenize='unicode61 remove_diacritics 2'
);

-- Triggers to keep FTS index in sync
CREATE TRIGGER entries_fts_insert AFTER INSERT ON entries BEGIN
    INSERT INTO entries_fts(rowid, path) 
    VALUES ((NEW.manifest_id << 32) | ROWID, NEW.path);
END;

CREATE TRIGGER entries_fts_delete AFTER DELETE ON entries BEGIN
    DELETE FROM entries_fts 
    WHERE rowid = (OLD.manifest_id << 32) | ROWID;
END;

-- ============================================================================
-- Views for Common Queries
-- ============================================================================

-- Latest version of each file
CREATE VIEW latest_entries AS
SELECT e.*
FROM entries e
INNER JOIN (
    SELECT path, MAX(m.created_at) as latest_date
    FROM entries e2
    JOIN manifests m ON e2.manifest_id = m.id
    GROUP BY path
) latest ON e.path = latest.path
JOIN manifests m2 ON e.manifest_id = m2.id AND m2.created_at = latest.latest_date;

-- Duplicate files across system
CREATE VIEW duplicates AS
SELECT 
    e1.path as path1,
    e2.path as path2,
    e1.size,
    hex(e1.checksum_xxh64) as checksum,
    m1.source_path || '/' || e1.path as full_path1,
    m2.source_path || '/' || e2.path as full_path2
FROM entries e1
JOIN entries e2 ON e1.checksum_xxh64 = e2.checksum_xxh64 
    AND e1.size = e2.size
    AND (e1.manifest_id < e2.manifest_id OR 
         (e1.manifest_id = e2.manifest_id AND e1.path < e2.path))
JOIN manifests m1 ON e1.manifest_id = m1.id
JOIN manifests m2 ON e2.manifest_id = m2.id
WHERE e1.checksum_xxh64 IS NOT NULL;

-- Files that changed between runs
CREATE VIEW changed_files AS
SELECT 
    ph.path,
    ph.change_count,
    ph.status,
    e.size as current_size,
    ph.last_size as previous_size,
    hex(e.checksum_xxh64) as current_checksum,
    hex(ph.last_checksum_xxh64) as previous_checksum
FROM path_history ph
JOIN entries e ON ph.path = e.path
WHERE ph.status = 'modified'
    AND e.manifest_id = ph.last_manifest_id;

-- ============================================================================
-- Maintenance Procedures (as SQL comments showing the queries to run)
-- ============================================================================

-- Run periodically to update statistics:
-- ANALYZE;

-- Run after large deletes to reclaim space:
-- PRAGMA incremental_vacuum;

-- Run to optimize query planner after schema changes:
-- PRAGMA optimize;

-- To check database integrity:
-- PRAGMA integrity_check;

-- To get database stats:
-- SELECT page_count * page_size / 1024 / 1024 AS size_mb FROM pragma_page_count(), pragma_page_size();