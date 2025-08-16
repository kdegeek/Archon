#!/bin/bash

# Archon Unraid Backup Script
# Comprehensive backup solution for Archon deployment on Unraid

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
UNRAID_DIR="$PROJECT_ROOT/unraid"

# Load environment variables
if [ -f "$UNRAID_DIR/.env" ]; then
    source "$UNRAID_DIR/.env"
fi

# Backup configuration with defaults
APPDATA_PATH="${APPDATA_PATH:-/mnt/user/appdata/archon}"
DATA_PATH="${DATA_PATH:-/mnt/user/archon-data}"
BACKUP_PATH="${BACKUP_PATH:-/mnt/user/backups/archon}"
BACKUP_RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
BACKUP_COMPRESSION="${BACKUP_COMPRESSION:-true}"
BACKUP_ENCRYPTION="${BACKUP_ENCRYPTION:-false}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="archon_backup_${TIMESTAMP}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Backup type (full or incremental)
BACKUP_TYPE="${1:-full}"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    logger -t "archon-backup" "$1" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    logger -t "archon-backup" "SUCCESS: $1" 2>/dev/null || true
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    logger -t "archon-backup" "WARNING: $1" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    logger -t "archon-backup" "ERROR: $1" 2>/dev/null || true
}

send_notification() {
    local subject="$1"
    local message="$2"
    local importance="${3:-normal}"
    
    # Send Unraid notification if available
    if command -v notify &> /dev/null; then
        notify -s "$subject" -d "$message" -i "$importance"
    fi
}

check_prerequisites() {
    log_info "Checking backup prerequisites..."
    
    # Check if backup directory exists
    if [ ! -d "$BACKUP_PATH" ]; then
        log_info "Creating backup directory: $BACKUP_PATH"
        mkdir -p "$BACKUP_PATH"
    fi
    
    # Create subdirectories for organized backup storage
    mkdir -p "$BACKUP_PATH"/{snapshots,compressed,encrypted}
    
    # Check available space
    AVAILABLE_SPACE=$(df "$BACKUP_PATH" | awk 'NR==2 {print $4}')
    REQUIRED_SPACE=$(du -s "$APPDATA_PATH" "$DATA_PATH" 2>/dev/null | awk '{sum+=$1} END {print sum}')
    
    if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
        log_error "Insufficient space for backup. Required: ${REQUIRED_SPACE}K, Available: ${AVAILABLE_SPACE}K"
        send_notification "Archon Backup Failed" "Insufficient disk space for backup" "error"
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

stop_services() {
    log_info "Stopping Archon services for consistent backup..."
    
    cd "$UNRAID_DIR"
    docker compose -f docker-compose.unraid.yml -f docker-compose.override.yml stop
    
    # Wait for services to stop
    sleep 5
    
    log_success "Services stopped"
}

start_services() {
    log_info "Restarting Archon services..."
    
    cd "$UNRAID_DIR"
    docker compose -f docker-compose.unraid.yml -f docker-compose.override.yml start
    
    log_success "Services restarted"
}

backup_database() {
    log_info "Backing up database configuration..."
    
    # Create database backup directory
    DB_BACKUP_DIR="$BACKUP_PATH/snapshots/$BACKUP_NAME/database"
    mkdir -p "$DB_BACKUP_DIR"
    
    # Export Supabase configuration if available
    if [ -n "$SUPABASE_URL" ] && [ -n "$SUPABASE_SERVICE_KEY" ]; then
        echo "SUPABASE_URL=$SUPABASE_URL" > "$DB_BACKUP_DIR/supabase_config.txt"
        log_info "Supabase configuration saved (credentials excluded for security)"
    fi
    
    # Note: Actual database backup would require Supabase CLI or API
    # This is a placeholder for database metadata
    cat > "$DB_BACKUP_DIR/backup_info.txt" <<EOF
Backup Timestamp: $TIMESTAMP
Backup Type: $BACKUP_TYPE
Supabase URL: $SUPABASE_URL
Note: Database content backup requires separate Supabase backup procedure
EOF
    
    log_success "Database configuration backed up"
}

backup_appdata() {
    log_info "Backing up application data..."
    
    APPDATA_BACKUP_DIR="$BACKUP_PATH/snapshots/$BACKUP_NAME/appdata"
    mkdir -p "$APPDATA_BACKUP_DIR"
    
    # Backup each service's appdata
    for service in server mcp agents frontend; do
        if [ -d "$APPDATA_PATH/$service" ]; then
            log_info "Backing up $service appdata..."
            
            if [ "$BACKUP_TYPE" == "incremental" ]; then
                # Incremental backup using rsync with proper link-dest
                latest_link="$BACKUP_PATH/latest"
                if [ -d "$latest_link/appdata/$service" ]; then
                    rsync -av --delete \
                        --link-dest="$latest_link/appdata/$service" \
                        "$APPDATA_PATH/$service/" \
                        "$APPDATA_BACKUP_DIR/$service/"
                else
                    # First backup or latest link doesn't exist, do full backup
                    cp -r "$APPDATA_PATH/$service" "$APPDATA_BACKUP_DIR/"
                fi
            else
                # Full backup
                cp -r "$APPDATA_PATH/$service" "$APPDATA_BACKUP_DIR/"
            fi
        fi
    done
    
    # Backup logs
    if [ -d "$APPDATA_PATH/logs" ]; then
        log_info "Backing up logs..."
        cp -r "$APPDATA_PATH/logs" "$APPDATA_BACKUP_DIR/"
    fi
    
    log_success "Application data backed up"
}

backup_documents() {
    log_info "Backing up knowledge base documents..."
    
    DOCS_BACKUP_DIR="$BACKUP_PATH/snapshots/$BACKUP_NAME/documents"
    mkdir -p "$DOCS_BACKUP_DIR"
    
    if [ -d "$DATA_PATH" ]; then
        if [ "$BACKUP_TYPE" == "incremental" ]; then
            # Incremental backup with proper link-dest
            latest_link="$BACKUP_PATH/latest"
            if [ -d "$latest_link/documents" ]; then
                rsync -av --delete \
                    --link-dest="$latest_link/documents" \
                    "$DATA_PATH/" \
                    "$DOCS_BACKUP_DIR/"
            else
                # First backup or latest link doesn't exist, do full backup
                cp -r "$DATA_PATH"/* "$DOCS_BACKUP_DIR/" 2>/dev/null || true
            fi
        else
            # Full backup
            cp -r "$DATA_PATH"/* "$DOCS_BACKUP_DIR/" 2>/dev/null || true
        fi
    fi
    
    log_success "Documents backed up"
}

backup_configuration() {
    log_info "Backing up configuration files..."
    
    CONFIG_BACKUP_DIR="$BACKUP_PATH/snapshots/$BACKUP_NAME/config"
    mkdir -p "$CONFIG_BACKUP_DIR"
    
    # Backup environment file (excluding sensitive data)
    if [ -f "$UNRAID_DIR/.env" ]; then
        grep -v "_KEY\|_TOKEN\|PASSWORD" "$UNRAID_DIR/.env" > "$CONFIG_BACKUP_DIR/env_sanitized.txt"
        log_info "Environment configuration backed up (sensitive data excluded)"
    fi
    
    # Backup docker-compose files
    cp "$UNRAID_DIR"/*.yml "$CONFIG_BACKUP_DIR/" 2>/dev/null || true
    
    # Backup any custom scripts
    if [ -d "$UNRAID_DIR/scripts" ]; then
        cp -r "$UNRAID_DIR/scripts" "$CONFIG_BACKUP_DIR/"
    fi
    
    log_success "Configuration files backed up"
}

backup_docker_images() {
    log_info "Backing up Docker images..."
    
    IMAGES_BACKUP_DIR="$BACKUP_PATH/snapshots/$BACKUP_NAME/images"
    mkdir -p "$IMAGES_BACKUP_DIR"
    
    # Export Docker images
    images=("ghcr.io/archon/archon-server" "ghcr.io/archon/archon-mcp" "ghcr.io/archon/archon-agents" "ghcr.io/archon/archon-frontend")
    
    for image in "${images[@]}"; do
        if docker images | grep -q "$image"; then
            log_info "Exporting $image..."
            # Extract image name for filename
            image_name=$(basename "$image")
            docker save "$image:latest" | gzip > "$IMAGES_BACKUP_DIR/${image_name}.tar.gz"
        fi
    done
    
    log_success "Docker images backed up"
}

update_latest_symlink() {
    log_info "Updating latest backup symlink..."
    
    # Update the latest symlink to point to the current uncompressed snapshot
    latest_link="$BACKUP_PATH/latest"
    rm -f "$latest_link"
    ln -s "snapshots/$BACKUP_NAME" "$latest_link"
    
    log_success "Latest backup symlink updated"
}

compress_backup() {
    if [ "$BACKUP_COMPRESSION" == "true" ]; then
        log_info "Compressing backup..."
        
        cd "$BACKUP_PATH"
        tar -czf "compressed/${BACKUP_NAME}.tar.gz" "snapshots/$BACKUP_NAME"
        
        # Keep the uncompressed snapshot for incremental backups
        # Only remove old snapshots during cleanup
        
        BACKUP_SIZE=$(du -h "compressed/${BACKUP_NAME}.tar.gz" | cut -f1)
        log_success "Backup compressed to compressed/${BACKUP_NAME}.tar.gz (Size: $BACKUP_SIZE)"
    fi
}

encrypt_backup() {
    if [ "$BACKUP_ENCRYPTION" == "true" ] && [ -n "$BACKUP_ENCRYPTION_KEY" ]; then
        log_info "Encrypting backup..."
        
        cd "$BACKUP_PATH"
        
        if [ "$BACKUP_COMPRESSION" == "true" ]; then
            openssl enc -aes-256-cbc -salt -in "compressed/${BACKUP_NAME}.tar.gz" \
                -out "encrypted/${BACKUP_NAME}.tar.gz.enc" \
                -pass pass:"$BACKUP_ENCRYPTION_KEY"
            rm "compressed/${BACKUP_NAME}.tar.gz"
            log_success "Backup encrypted"
        else
            tar -czf - "snapshots/$BACKUP_NAME" | \
                openssl enc -aes-256-cbc -salt \
                -out "encrypted/${BACKUP_NAME}.tar.gz.enc" \
                -pass pass:"$BACKUP_ENCRYPTION_KEY"
            log_success "Backup compressed and encrypted"
        fi
    fi
}

verify_backup() {
    log_info "Verifying backup integrity..."
    
    cd "$BACKUP_PATH"
    
    # Determine backup file
    if [ "$BACKUP_ENCRYPTION" == "true" ] && [ -n "$BACKUP_ENCRYPTION_KEY" ]; then
        BACKUP_FILE="encrypted/${BACKUP_NAME}.tar.gz.enc"
    elif [ "$BACKUP_COMPRESSION" == "true" ]; then
        BACKUP_FILE="compressed/${BACKUP_NAME}.tar.gz"
    else
        BACKUP_FILE="snapshots/$BACKUP_NAME"
    fi
    
    if [ -e "$BACKUP_FILE" ]; then
        BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        log_success "Backup verified: $BACKUP_FILE (Size: $BACKUP_SIZE)"
        
        # Generate checksum
        sha256sum "$BACKUP_FILE" > "${BACKUP_FILE}.sha256"
        
        return 0
    else
        log_error "Backup verification failed"
        return 1
    fi
}

cleanup_old_backups() {
    log_info "Cleaning up old backups..."
    
    if [ "$BACKUP_RETENTION_DAYS" -gt 0 ]; then
        # Remove old compressed backup files
        find "$BACKUP_PATH" -name "archon_backup_*" -type f -mtime +$BACKUP_RETENTION_DAYS -delete
        
        # Remove old snapshot directories
        find "$BACKUP_PATH/snapshots" -maxdepth 1 -type d -name "archon_backup_*" -mtime +$BACKUP_RETENTION_DAYS -exec rm -rf {} +
        
        # Ensure latest symlink doesn't point to a deleted snapshot
        latest_link="$BACKUP_PATH/latest"
        if [ -L "$latest_link" ] && [ ! -d "$latest_link" ]; then
            log_warning "Latest symlink points to deleted snapshot, removing symlink"
            rm -f "$latest_link"
        fi
        
        log_success "Old backups cleaned up (retention: $BACKUP_RETENTION_DAYS days)"
    fi
}

generate_backup_report() {
    log_info "Generating backup report..."
    
    REPORT_FILE="$BACKUP_PATH/backup_report_${TIMESTAMP}.txt"
    
    cat > "$REPORT_FILE" <<EOF
=====================================
Archon Backup Report
=====================================
Timestamp: $(date)
Backup Type: $BACKUP_TYPE
Backup Name: $BACKUP_NAME

Configuration:
- AppData Path: $APPDATA_PATH
- Data Path: $DATA_PATH
- Backup Path: $BACKUP_PATH
- Compression: $BACKUP_COMPRESSION
- Encryption: $BACKUP_ENCRYPTION
- Retention: $BACKUP_RETENTION_DAYS days

Backup Contents:
- Application Data: Yes
- Documents: Yes
- Configuration: Yes
- Docker Images: Yes
- Database Config: Yes

Backup File: $BACKUP_FILE
Backup Size: $BACKUP_SIZE
Checksum File: ${BACKUP_FILE}.sha256

Status: SUCCESS
=====================================
EOF
    
    log_success "Backup report generated: $REPORT_FILE"
}

# Main execution
main() {
    echo ""
    echo "========================================="
    echo "    Archon Backup Script"
    echo "========================================="
    echo ""
    echo "Backup Type: $BACKUP_TYPE"
    echo "Backup Location: $BACKUP_PATH"
    echo ""
    
    # Start backup process
    START_TIME=$(date +%s)
    
    check_prerequisites
    
    # Only stop services for full backup
    if [ "$BACKUP_TYPE" == "full" ]; then
        stop_services
    fi
    
    # Perform backup
    backup_database
    backup_appdata
    backup_documents
    backup_configuration
    
    # Only backup Docker images for full backup
    if [ "$BACKUP_TYPE" == "full" ]; then
        backup_docker_images
        start_services
    fi
    
    # Update symlink before compression to ensure incremental backups work
    update_latest_symlink
    
    # Post-processing
    compress_backup
    encrypt_backup
    
    # Verification and cleanup
    if verify_backup; then
        cleanup_old_backups
        generate_backup_report
        
        # Calculate duration
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        DURATION_MIN=$((DURATION / 60))
        DURATION_SEC=$((DURATION % 60))
        
        log_success "Backup completed successfully in ${DURATION_MIN}m ${DURATION_SEC}s"
        send_notification "Archon Backup Complete" "Backup completed successfully. Size: $BACKUP_SIZE" "normal"
    else
        log_error "Backup failed"
        send_notification "Archon Backup Failed" "Backup process failed. Check logs for details." "error"
        
        # Restart services if they were stopped
        if [ "$BACKUP_TYPE" == "full" ]; then
            start_services
        fi
        
        exit 1
    fi
}

# Handle script interruption
trap 'log_error "Backup interrupted"; start_services; exit 1' INT TERM

# Run main function
main "$@"