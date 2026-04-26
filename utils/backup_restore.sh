#!/bin/bash
# ============================================================
# utils/backup_restore.sh
# MySQL backup and restore utilities
# ============================================================

DB_USER="root"
DB_PASS="your_password"
DB_HOST="localhost"
DB_NAME="practice_db"
BACKUP_DIR="/var/backups/mysql"
DATE=$(date +%Y%m%d_%H%M%S)

# ── Full backup (logical) ─────────────────────────────────────
backup_logical() {
    echo "Starting logical backup of $DB_NAME..."
    mkdir -p "$BACKUP_DIR"
    mysqldump \
        -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" \
        --single-transaction \
        --routines \
        --triggers \
        --events \
        --set-gtid-purged=OFF \
        "$DB_NAME" | gzip > "$BACKUP_DIR/${DB_NAME}_${DATE}.sql.gz"
    echo "Backup saved: $BACKUP_DIR/${DB_NAME}_${DATE}.sql.gz"
}

# ── Restore from backup ───────────────────────────────────────
restore_logical() {
    local backup_file="$1"
    if [ -z "$backup_file" ]; then
        echo "Usage: restore_logical <backup_file.sql.gz>"
        exit 1
    fi
    echo "Restoring $DB_NAME from $backup_file..."
    gunzip -c "$backup_file" | mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" "$DB_NAME"
    echo "Restore complete."
}

# ── Backup all databases ──────────────────────────────────────
backup_all() {
    echo "Backing up all databases..."
    mysqldump \
        -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" \
        --all-databases \
        --single-transaction \
        --routines --triggers --events \
        | gzip > "$BACKUP_DIR/all_databases_${DATE}.sql.gz"
    echo "All databases backed up."
}

# ── Point-in-time recovery setup ─────────────────────────────
# Requires binary logging enabled
enable_binlog_backup() {
    # Flush and backup binary logs
    mysql -u "$DB_USER" -p"$DB_PASS" -h "$DB_HOST" -e "FLUSH BINARY LOGS;"
    cp /var/lib/mysql/binlog.* "$BACKUP_DIR/binlogs_${DATE}/"
}

# ── Verify backup integrity ───────────────────────────────────
verify_backup() {
    local backup_file="$1"
    echo "Verifying backup: $backup_file"
    gunzip -t "$backup_file" && echo "Backup file is valid." || echo "Backup file is CORRUPTED!"
}

# ── Cleanup old backups (keep last 7 days) ────────────────────
cleanup_old_backups() {
    find "$BACKUP_DIR" -name "*.sql.gz" -mtime +7 -delete
    echo "Old backups cleaned up."
}

# ── Main ──────────────────────────────────────────────────────
case "$1" in
    backup)   backup_logical ;;
    restore)  restore_logical "$2" ;;
    backup-all) backup_all ;;
    verify)   verify_backup "$2" ;;
    cleanup)  cleanup_old_backups ;;
    *)
        echo "Usage: $0 {backup|restore <file>|backup-all|verify <file>|cleanup}"
        exit 1
        ;;
esac
