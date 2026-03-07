#!/usr/bin/env python
# =============================================================================
# Genomics Core Project Tracker - Beautiful Rich Version
# Usage: python project_tracker.py list | active | update | search | history | summary
# =============================================================================
from rich.console import Console
from rich.table import Table
from rich.panel import Panel
from rich import print as rprint
from rich.text import Text
import sqlite3
import argparse
import sys
from datetime import datetime

DB_PATH = "/home/ja581385/genomics_core/projects/project_tracker.db"
console = Console()

STATUS_COLORS = {
    "initialized": "yellow",
    "running": "blue",
    "completed": "green",
    "failed": "red",
    "archived": "dim"
}

def get_db():
    return sqlite3.connect(DB_PATH)

def colored_status(status: str) -> Text:
    color = STATUS_COLORS.get(status.lower(), "white")
    return Text(status.upper(), style=f"bold {color}")

def main():
    parser = argparse.ArgumentParser(description="🧬 Genomics Core Project Tracker")
    parser.add_argument("command", choices=["list", "active", "update", "search", "history", "summary"])
    parser.add_argument("project_id", nargs="?", help="Project ID (for update/history)")
    parser.add_argument("new_status", nargs="?", help="New status (for update)")
    parser.add_argument("--notes", "-n", default="", help="Notes for update")
    args = parser.parse_args()

    console.rule("[bold cyan]🧬 Genomics Core Project Tracker[/bold cyan]")

    if args.command == "list":
        show_list()
    elif args.command == "active":
        show_active()
    elif args.command == "update":
        if not args.project_id or not args.new_status:
            console.print("[red]Error: project_id and new_status required[/red]")
            sys.exit(1)
        update_project(args.project_id, args.new_status, args.notes)
    elif args.command == "search":
        if not args.project_id:
            console.print("[red]Error: search term required[/red]")
            sys.exit(1)
        search(args.project_id)
    elif args.command == "history":
        show_history(args.project_id)
    elif args.command == "summary":
        show_summary()

def show_list():
    conn = get_db()
    rows = conn.execute("""
        SELECT project_id, status, pi_name, analyst, organism, num_samples, last_updated 
        FROM projects ORDER BY last_updated DESC
    """).fetchall()
    conn.close()

    table = Table(title="All Projects", show_header=True, header_style="bold magenta")
    table.add_column("Project ID", style="cyan")
    table.add_column("Status", justify="center")
    table.add_column("PI")
    table.add_column("Analyst")
    table.add_column("Organism")
    table.add_column("Samples", justify="right")
    table.add_column("Last Updated")

    for row in rows:
        table.add_row(
            row[0],
            colored_status(row[1]),
            row[2],
            row[3],
            row[4] or "-",
            str(row[5] or "-"),
            row[6][:10] if row[6] else "-"
        )

    console.print(table)

def show_active():
    conn = get_db()
    rows = conn.execute("""
        SELECT project_id, status, pi_name, analyst, organism, num_samples 
        FROM v_active_projects ORDER BY last_updated DESC
    """).fetchall()
    conn.close()

    table = Table(title="🚀 Active Projects", show_header=True, header_style="bold green")
    for col in ["Project ID", "Status", "PI", "Analyst", "Organism", "Samples"]:
        table.add_column(col, justify="center" if col in ["Status","Samples"] else "left")
    
    for row in rows:
        table.add_row(row[0], colored_status(row[1]), row[2], row[3], row[4] or "-", str(row[5] or "-"))
    
    console.print(table)

def update_project(project_id: str, new_status: str, notes: str):
    conn = get_db()
    cur = conn.cursor()
    
    # Get old status
    cur.execute("SELECT status FROM projects WHERE project_id=?", (project_id,))
    old = cur.fetchone()
    if not old:
        console.print(f"[red]Project {project_id} not found![/red]")
        return
    
    old_status = old[0]
    
    # Update project
    cur.execute("""
        UPDATE projects 
        SET status=?, last_updated=datetime('now') 
        WHERE project_id=?
    """, (new_status, project_id))
    
    # Add history
    cur.execute("""
        INSERT INTO project_history (project_id, old_status, new_status, changed_by, notes)
        VALUES (?, ?, ?, ?, ?)
    """, (project_id, old_status, new_status, "jash", notes))
    
    conn.commit()
    conn.close()
    
    console.print(Panel(
        f"[green]✅ Updated[/green] {project_id}\n"
        f"[yellow]{old_status}[/yellow] → [bold]{colored_status(new_status)}[/bold]",
        title="Status Updated",
        style="green"
    ))

def search(term: str):
    conn = get_db()
    rows = conn.execute("""
        SELECT project_id, status, pi_name, analyst, organism 
        FROM projects 
        WHERE project_id LIKE ? OR pi_name LIKE ? OR analyst LIKE ?
    """, (f"%{term}%", f"%{term}%", f"%{term}%")).fetchall()
    conn.close()

    if not rows:
        console.print(f"[yellow]No matches for '{term}'[/yellow]")
        return

    table = Table(title=f"🔍 Search Results: {term}")
    table.add_column("Project ID")
    table.add_column("Status")
    table.add_column("PI")
    table.add_column("Analyst")
    table.add_column("Organism")
    
    for row in rows:
        table.add_row(row[0], colored_status(row[1]), row[2], row[3], row[4] or "-")
    
    console.print(table)

def show_history(project_id=None):
    conn = get_db()
    if project_id:
        rows = conn.execute("""
            SELECT changed_at, old_status, new_status, changed_by, notes 
            FROM project_history WHERE project_id=? ORDER BY changed_at DESC
        """, (project_id,)).fetchall()
        title = f"History for {project_id}"
    else:
        rows = conn.execute("SELECT * FROM project_history ORDER BY changed_at DESC LIMIT 30").fetchall()
        title = "Recent Changes (Last 30)"
    
    conn.close()

    table = Table(title=title)
    table.add_column("Date")
    table.add_column("Old → New")
    table.add_column("By")
    table.add_column("Notes")
    
    for row in rows:
        table.add_row(
            row[0][:16],
            f"{row[1]} → {colored_status(row[2])}",
            row[3],
            row[4] or "-"
        )
    
    console.print(table)

def show_summary():
    conn = get_db()
    stats = conn.execute("""
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN status='running' THEN 1 ELSE 0 END) as running,
            SUM(CASE WHEN status='completed' THEN 1 ELSE 0 END) as completed,
            SUM(CASE WHEN status='archived' THEN 1 ELSE 0 END) as archived,
            SUM(CASE WHEN status='failed' THEN 1 ELSE 0 END) as failed
        FROM projects
    """).fetchone()
    conn.close()

    console.print(Panel(
        f"Total Projects : [bold cyan]{stats[0]}[/bold cyan]\n"
        f"🚀 Running     : [bold blue]{stats[1] or 0}[/bold blue]\n"
        f"✅ Completed   : [bold green]{stats[2] or 0}[/bold green]\n"
        f"📦 Archived    : [dim]{stats[3] or 0}[/dim]\n"
        f"❌ Failed      : [red]{stats[4] or 0}[/red]",
        title="📊 Project Summary",
        expand=False
    ))

if __name__ == "__main__":
    main()
