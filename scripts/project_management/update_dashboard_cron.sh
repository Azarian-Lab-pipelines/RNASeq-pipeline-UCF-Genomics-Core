# scripts/project_management/update_dashboard_cron.sh
#!/bin/bash
set -euo pipefail

cd /home/ja581385/genomics_core || exit 1
source bin/activate_genomics_core.sh >/dev/null 2>&1

python scripts/project_management/generate_dashboard.py

git add -u docs/index.html
git diff --cached --quiet && {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] No changes" >> logs/dashboard_cron.log
    exit 0
}

git commit -m "Auto-update dashboard [skip ci]" || exit 0
git push origin main >> logs/dashboard_cron.log 2>&1 || {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Push failed" >> logs/dashboard_cron.log
    exit 1
}
