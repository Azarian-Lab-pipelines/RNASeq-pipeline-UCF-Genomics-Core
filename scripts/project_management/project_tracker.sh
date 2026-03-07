#!/bin/bash
# =============================================================================
# Genomics Core Project Tracker CLI
# Usage: ./project_tracker.sh <command> [args]
# Commands: list, update, search, history, summary
# =============================================================================
set -euo pipefail
BASE="/home/ja581385/genomics_core"
DB="${BASE}/projects/project_tracker.db"
USER="$(whoami)"

cmd="${1:-list}"
shift || true

case "${cmd}" in
    list)
        sqlite3 -header -column "${DB}" "
            SELECT project_id, status, pi_name, analyst, organism, num_samples, last_updated
            FROM projects
            ORDER BY last_updated DESC;
        "
        ;;
    active)
        sqlite3 -header -column "${DB}" "
            SELECT project_id, pi_name, analyst, organism, num_samples
            FROM v_active_projects
            ORDER BY last_updated DESC;
        "
        ;;
    update)
        proj_id="${1:?Usage: project_tracker.sh update <PROJECT_ID> <new_status> [notes]}"
        new_status="${2:?Usage: project_tracker.sh update <PROJECT_ID> <new_status> [notes]}"
        notes="${3:-}"
        old_status=$(sqlite3 "${DB}" "SELECT status FROM projects WHERE project_id='${proj_id}';")
        
        sqlite3 "${DB}" "
            UPDATE projects SET status='${new_status}', last_updated=datetime('now')
            WHERE project_id='${proj_id}';
            
            INSERT INTO project_history (project_id, old_status, new_status, changed_by, notes)
            VALUES ('${proj_id}', '${old_status}', '${new_status}', '${USER}', '${notes//\'/\'\'}');
        "
        echo "✅ Updated ${proj_id}: ${old_status} → ${new_status}"
        ;;
    search)
        term="${1:?Usage: project_tracker.sh search <PI or PROJECT_ID>}"
        sqlite3 -header -column "${DB}" "
            SELECT * FROM projects
            WHERE project_id LIKE '%${term}%'
               OR pi_name LIKE '%${term}%'
               OR analyst LIKE '%${term}%';
        "
        ;;
    history)
        proj_id="${1}"
        if [ -n "${proj_id}" ]; then
            sqlite3 -header -column "${DB}" "
                SELECT changed_at, old_status, new_status, changed_by, notes
                FROM project_history WHERE project_id='${proj_id}'
                ORDER BY changed_at DESC;
            "
        else
            sqlite3 -header -column "${DB}" "SELECT * FROM project_history ORDER BY changed_at DESC LIMIT 20;"
        fi
        ;;
    summary)
        sqlite3 "${DB}" "
            SELECT 
                COUNT(*) as total,
                SUM(CASE WHEN status='running' THEN 1 ELSE 0 END) as running,
                SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed,
                SUM(CASE WHEN status='archived' THEN 1 ELSE 0 END) as archived
            FROM projects;
        " | column -t
        ;;
    *)
        echo "Usage: project_tracker.sh [list|active|update|search|history|summary]"
        echo "Example: ./project_tracker.sh update PROJ-2026-001 running \"Started alignment\""
        ;;
esac
