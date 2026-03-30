#!/bin/bash
# Daily SQLite backup script for eBook Organizer
# Add to cron: 0 3 * * * /opt/ebook-organizer/deploy/backup.sh

BACKUP_DIR="/mnt/library/_backups"
DB_PATH="/opt/ebook-organizer/data/ebook_organizer.db"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "$BACKUP_DIR"

# Use SQLite's backup command (safe with WAL mode)
sqlite3 "$DB_PATH" ".backup '$BACKUP_DIR/ebook_organizer_$DATE.db'"

if [ $? -eq 0 ]; then
    echo "Backup successful: ebook_organizer_$DATE.db"
else
    echo "Backup FAILED!" >&2
    exit 1
fi

# Keep only last 7 daily backups
find "$BACKUP_DIR" -name "ebook_organizer_*.db" -mtime +7 -delete

echo "Backup complete. $(ls "$BACKUP_DIR"/ebook_organizer_*.db 2>/dev/null | wc -l) backup(s) retained."
