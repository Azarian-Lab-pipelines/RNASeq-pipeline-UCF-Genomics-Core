#!/bin/bash
set -euo pipefail
BASE="/home/ja581385/genomics_core"
DB="${BASE}/projects/project_tracker.db"

echo "Importing existing projects from metadata.yaml files..."

for meta in ${BASE}/projects/{active,completed,failed}/*/project_metadata.yaml ${BASE}/archive/*/*/project_metadata.yaml; do
    [ -f "${meta}" ] || continue
    proj_dir=$(dirname "${meta}")
    proj_id=$(basename "${proj_dir}")

    # Extract values (safe yaml parsing with yq or grep)
    status=$(grep "^status:" "${meta}" | awk '{print $2}' | tr -d '"' || echo "initialized")
    pi=$(grep "^pi_name:" "${meta}" | awk '{$1=""; print $0}' | xargs || echo "Unknown")
    analyst=$(grep "^analyst:" "${meta}" | awk '{$1=""; print $0}' | xargs || echo "Unknown")
    organism=$(grep "^organism:" "${meta}" | awk '{print $2}' | tr -d '"' || echo "")
    received=$(grep "^date_received:" "${meta}" | awk '{print $2}' | tr -d '"' || echo "")
    completed=$(grep "^date_completed:" "${meta}" | awk '{print $2}' | tr -d '"' || echo "")

    # Insert or update
    sqlite3 "${DB}" "
        INSERT OR REPLACE INTO projects (
            project_id, pi_name, analyst, organism, date_received, date_completed, status,
            active_path, archive_path, last_updated
        ) VALUES (
            '${proj_id}',
            '${pi//\'/\'\'}',
            '${analyst//\'/\'\'}',
            '${organism}',
            '${received}',
            '${completed}',
            '${status}',
            CASE WHEN '${proj_dir}' LIKE '%/active/%' THEN '${proj_dir}' ELSE NULL END,
            CASE WHEN '${proj_dir}' LIKE '%/archive/%' THEN '${proj_dir}' ELSE NULL END,
            datetime('now')
        );
    "

    echo "Imported: ${proj_id} → ${status}"
done

echo ""
echo "✅ Migration complete! You now have a central project tracker."
echo "Try: ./scripts/project_management/project_tracker.sh list"
