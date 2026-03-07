#!/bin/bash
# =============================================================================
# Initialize central Project Tracker SQLite database
# Location: /home/ja581385/genomics_core/projects/project_tracker.db
# =============================================================================
set -euo pipefail
BASE="/home/ja581385/genomics_core"
DB="${BASE}/projects/project_tracker.db"

echo "============================================="
echo "Creating/Initializing Project Tracker Database"
echo "Database: ${DB}"
echo "============================================="

# Create DB and tables
sqlite3 "${DB}" << 'SQL'
PRAGMA foreign_keys = ON;

-- Main projects table
CREATE TABLE IF NOT EXISTS projects (
    project_id          TEXT PRIMARY KEY,
    pi_name             TEXT,
    pi_email            TEXT,
    department          TEXT,
    analyst             TEXT,
    date_received       TEXT,
    date_started        TEXT,
    date_completed      TEXT,
    status              TEXT CHECK(status IN ('initialized','running','completed','failed','archived')),
    organism            TEXT,
    genome_build        TEXT,
    num_samples         INTEGER,
    pipeline            TEXT DEFAULT 'nf-core/rnaseq',
    pipeline_version    TEXT DEFAULT '3.23.0',
    notes               TEXT,
    active_path         TEXT,
    archive_path        TEXT,
    created_at          TEXT DEFAULT (datetime('now')),
    last_updated        TEXT DEFAULT (datetime('now'))
);

-- Audit/history table
CREATE TABLE IF NOT EXISTS project_history (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id      TEXT,
    old_status      TEXT,
    new_status      TEXT,
    changed_by      TEXT,
    changed_at      TEXT DEFAULT (datetime('now')),
    notes           TEXT,
    FOREIGN KEY (project_id) REFERENCES projects(project_id)
);

-- Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_status ON projects(status);
CREATE INDEX IF NOT EXISTS idx_pi ON projects(pi_name);
CREATE INDEX IF NOT EXISTS idx_analyst ON projects(analyst);

-- View for quick summary
CREATE VIEW IF NOT EXISTS v_active_projects AS
    SELECT project_id, pi_name, analyst, organism, num_samples, status, last_updated
    FROM projects
    WHERE status IN ('initialized','running','completed');
SQL

echo "✅ Database created at ${DB}"
echo "Tables: projects + project_history + view v_active_projects"
echo ""
echo "Next: Run the migration script to import your existing projects."
