#!/usr/bin/env python
# =============================================================================
# Genomics Core Public Dashboard Generator
# Creates a beautiful static HTML dashboard from your SQLite tracker
# Run this script anytime → commit → GitHub Pages shows the latest status
# =============================================================================
import sqlite3
from datetime import datetime
import os

DB_PATH = "/home/ja581385/genomics_core/projects/project_tracker.db"
OUTPUT_DIR = "/home/ja581385/genomics_core/dashboard"
OUTPUT_FILE = f"{OUTPUT_DIR}/index.html"

HTML_TEMPLATE = """<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>🧬 Genomics Core - Project Status</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.0/css/all.min.css">
    <style>
        .status-badge { padding: 4px 12px; border-radius: 9999px; font-weight: 600; font-size: 0.85rem; }
        .search-input { transition: all 0.3s; }
        .search-input:focus { box-shadow: 0 0 0 3px rgba(59, 130, 246, 0.3); }
    </style>
</head>
<body class="bg-gray-950 text-gray-200">
    <div class="max-w-7xl mx-auto p-8">
        <!-- Header -->
        <div class="flex justify-between items-center mb-10">
            <div>
                <h1 class="text-4xl font-bold text-white flex items-center gap-3">
                    🧬 Genomics Core Facility
                    <span class="text-emerald-400 text-2xl">• Live Dashboard</span>
                </h1>
                <p class="text-gray-400 mt-1">Real-time RNA-seq project tracking • nf-core/rnaseq v3.23.0</p>
            </div>
            <div class="text-right">
                <div id="last-updated" class="text-sm text-gray-500"></div>
            </div>
        </div>

        <!-- Summary Cards -->
        <div class="grid grid-cols-2 md:grid-cols-4 gap-6 mb-12" id="summary-cards">
            <!-- Filled by JS -->
        </div>

        <!-- Search -->
        <div class="mb-6">
            <input type="text" id="search" placeholder="Search by Project ID, PI, or Analyst..." 
                   class="search-input w-full bg-gray-900 border border-gray-700 rounded-xl px-5 py-4 text-lg focus:outline-none">
        </div>

        <!-- Projects Table -->
        <div class="bg-gray-900 rounded-2xl overflow-hidden border border-gray-800">
            <table class="w-full" id="projects-table">
                <thead class="bg-gray-800">
                    <tr>
                        <th class="px-6 py-5 text-left font-semibold">Project ID</th>
                        <th class="px-6 py-5 text-center font-semibold">Status</th>
                        <th class="px-6 py-5 text-left font-semibold">PI</th>
                        <th class="px-6 py-5 text-left font-semibold">Analyst</th>
                        <th class="px-6 py-5 text-center font-semibold">Organism</th>
                        <th class="px-6 py-5 text-center font-semibold">Samples</th>
                        <th class="px-6 py-5 text-center font-semibold">Last Updated</th>
                    </tr>
                </thead>
                <tbody class="divide-y divide-gray-800" id="table-body">
                    <!-- Filled by JS -->
                </tbody>
            </table>
        </div>

        <div class="text-center mt-10 text-gray-500 text-sm">
            Last generated: <span id="generated-time"></span> • 
            <a href="https://github.com/YOUR_USERNAME/YOUR_REPO" target="_blank" 
               class="text-blue-400 hover:underline">View on GitHub</a>
        </div>
    </div>

    <script>
        const projects = __PROJECTS_DATA__;
        const lastUpdated = "__LAST_UPDATED__";

        // Render summary cards
        function renderSummary() {
            const counts = {
                running: projects.filter(p => p.status === "running").length,
                completed: projects.filter(p => p.status === "completed").length,
                archived: projects.filter(p => p.status === "archived").length,
                total: projects.length
            };
            document.getElementById("summary-cards").innerHTML = `
                <div class="bg-gradient-to-br from-blue-900 to-blue-950 p-6 rounded-2xl">
                    <div class="text-blue-400 text-4xl mb-2">🚀</div>
                    <div class="text-5xl font-bold">${counts.running}</div>
                    <div class="text-gray-400">Running</div>
                </div>
                <div class="bg-gradient-to-br from-emerald-900 to-emerald-950 p-6 rounded-2xl">
                    <div class="text-emerald-400 text-4xl mb-2">✅</div>
                    <div class="text-5xl font-bold">${counts.completed}</div>
                    <div class="text-gray-400">Completed</div>
                </div>
                <div class="bg-gradient-to-br from-amber-900 to-amber-950 p-6 rounded-2xl">
                    <div class="text-amber-400 text-4xl mb-2">📦</div>
                    <div class="text-5xl font-bold">${counts.archived}</div>
                    <div class="text-gray-400">Archived</div>
                </div>
                <div class="bg-gray-900 p-6 rounded-2xl border border-gray-700">
                    <div class="text-4xl mb-2">📊</div>
                    <div class="text-5xl font-bold">${counts.total}</div>
                    <div class="text-gray-400">Total Projects</div>
                </div>
            `;
        }

        // Render table
        function renderTable(filteredProjects) {
            const tbody = document.getElementById("table-body");
            tbody.innerHTML = "";
            filteredProjects.forEach(p => {
                const statusClass = {
                    "running": "bg-blue-500 text-white",
                    "completed": "bg-emerald-500 text-white",
                    "archived": "bg-gray-600 text-white",
                    "initialized": "bg-yellow-500 text-black",
                    "failed": "bg-red-500 text-white"
                }[p.status] || "bg-gray-600 text-white";

                const row = document.createElement("tr");
                row.className = "hover:bg-gray-800 transition-colors";
                row.innerHTML = `
                    <td class="px-6 py-5 font-mono text-blue-400">${p.project_id}</td>
                    <td class="px-6 py-5 text-center">
                        <span class="status-badge ${statusClass}">${p.status.toUpperCase()}</span>
                    </td>
                    <td class="px-6 py-5">${p.pi_name}</td>
                    <td class="px-6 py-5">${p.analyst}</td>
                    <td class="px-6 py-5 text-center">${p.organism || "-"}</td>
                    <td class="px-6 py-5 text-center">${p.num_samples || "-"}</td>
                    <td class="px-6 py-5 text-center text-sm text-gray-400">${p.last_updated}</td>
                `;
                tbody.appendChild(row);
            });
        }

        // Search functionality
        document.getElementById("search").addEventListener("input", (e) => {
            const term = e.target.value.toLowerCase();
            const filtered = projects.filter(p => 
                p.project_id.toLowerCase().includes(term) ||
                (p.pi_name || "").toLowerCase().includes(term) ||
                (p.analyst || "").toLowerCase().includes(term)
            );
            renderTable(filtered);
        });

        // Init
        renderSummary();
        renderTable(projects);
        document.getElementById("last-updated").textContent = `Last updated: ${lastUpdated}`;
        document.getElementById("generated-time").textContent = new Date().toLocaleString();
    </script>
</body>
</html>
"""

def generate_dashboard():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute("""
        SELECT project_id, status, pi_name, analyst, organism, num_samples, 
               substr(last_updated, 1, 16) as last_updated
        FROM projects 
        ORDER BY last_updated DESC
    """).fetchall()
    conn.close()

    projects_data = [dict(row) for row in rows]
    last_updated = datetime.now().strftime("%Y-%m-%d %H:%M")

    html = HTML_TEMPLATE.replace("__PROJECTS_DATA__", str(projects_data))
    html = html.replace("__LAST_UPDATED__", last_updated)

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(OUTPUT_FILE, "w", encoding="utf-8") as f:
        f.write(html)

    print(f"✅ Dashboard generated: {OUTPUT_FILE}")
    print(f"   {len(projects_data)} projects • Last updated: {last_updated}")
    print("\nNext step: Commit & push this folder to GitHub, then enable GitHub Pages!")

if __name__ == "__main__":
    generate_dashboard()
