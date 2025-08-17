#!/bin/bash

# Archon Unraid Restore Script
# Restore Archon deployment from backup

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
UNRAID_DIR="$PROJECT_ROOT/unraid"

# Load environment variables
if [ -f "$UNRAID_DIR/.env" ]; then
    source "$UNRAID_DIR/.env"
fi

# Restore configuration with defaults
APPDATA_PATH="${APPDATA_PATH:-/mnt/user/appdata/archon}"
DATA_PATH="${DATA_PATH:-/mnt/user/archon-data}"
BACKUP_PATH="${BACKUP_PATH:-/mnt/user/backups/archon}"
BACKUP_ENCRYPTION="${BACKUP_ENCRYPTION:-false}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Backup file to restore from (can be passed as argument)
BACKUP_FILE="${1:-latest}"

# Files to preserve during restore (will be backed up and restored)
PRESERVE_FILES=(".env" "custom.conf" "user-settings.json" "ssh_keys" "certificates")

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    logger -t "archon-restore" "$1" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    logger -t "archon-restore" "SUCCESS: $1" 2>/dev/null || true
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    logger -t "archon-restore" "WARNING: $1" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    logger -t "archon-restore" "ERROR: $1" 2>/dev/null || true
}

send_notification() {
    local subject="$1"
    local message="$2"
    local importance="${3:-normal}"
    
    if command -v notify &> /dev/null; then
        notify -s "$subject" -d "$message" -i "$importance"
    fi
}

select_backup() {
    log_info "Selecting backup to restore..."
    
    cd "$BACKUP_PATH"
    
    if [ "$BACKUP_FILE" == "latest" ]; then
        # Check if latest symlink exists and use that
        if [ -L "latest" ] && [ -d "latest" ]; then
            BACKUP_FILE=$(readlink "latest")
            log_info "Using latest backup: $BACKUP_FILE"
        else
            # Look for newest compressed backup
            BACKUP_FILE=$(ls -t compressed/archon_backup_*.tar.gz* 2>/dev/null | head -1)
            if [ -n "$BACKUP_FILE" ]; then
                BACKUP_FILE=$(basename "$BACKUP_FILE")
                log_info "Found compressed backup: $BACKUP_FILE"
            else
                # Fallback to newest snapshot directory
                BACKUP_FILE=$(ls -td snapshots/archon_backup_* 2>/dev/null | head -1)
                if [ -n "$BACKUP_FILE" ]; then
                    BACKUP_FILE=$(basename "$BACKUP_FILE")
                    log_info "Found snapshot backup: $BACKUP_FILE"
                else
                    log_error "No backup files found in $BACKUP_PATH"
                    exit 1
                fi
            fi
        fi
    elif [ ! -f "$BACKUP_PATH/$BACKUP_FILE" ] && [ ! -d "$BACKUP_PATH/$BACKUP_FILE" ] && [ ! -f "$BACKUP_PATH/compressed/$BACKUP_FILE" ] && [ ! -d "$BACKUP_PATH/snapshots/$BACKUP_FILE" ]; then
        log_error "Backup file not found: $BACKUP_FILE"
        exit 1
    fi
    
    # Determine full path based on backup type
    if [ -f "$BACKUP_PATH/compressed/$BACKUP_FILE" ]; then
        BACKUP_FILE_PATH="$BACKUP_PATH/compressed/$BACKUP_FILE"
    elif [ -d "$BACKUP_PATH/snapshots/$BACKUP_FILE" ]; then
        BACKUP_FILE_PATH="$BACKUP_PATH/snapshots/$BACKUP_FILE"
    elif [ -f "$BACKUP_PATH/$BACKUP_FILE" ]; then
        BACKUP_FILE_PATH="$BACKUP_PATH/$BACKUP_FILE"
    else
        BACKUP_FILE_PATH="$BACKUP_PATH/$BACKUP_FILE"
    fi
    
    log_success "Backup selected: $BACKUP_FILE"
}

verify_backup_integrity() {
    log_info "Verifying backup integrity..."
    
    # Check if checksum file exists
    if [ -f "${BACKUP_FILE_PATH}.sha256" ]; then
        log_info "Verifying checksum..."
        
        cd "$BACKUP_PATH"
        if sha256sum -c "${BACKUP_FILE}.sha256" &>/dev/null; then
            log_success "Backup integrity verified"
        else
            log_error "Backup integrity check failed"
            exit 1
        fi
    else
        log_warning "No checksum file found, skipping integrity check"
    fi
}

decrypt_backup() {
    if [[ "$BACKUP_FILE" == *.enc ]]; then
        log_info "Decrypting backup..."
        
        if [ -z "$BACKUP_ENCRYPTION_KEY" ]; then
            echo -n "Enter encryption key: "
            read -s BACKUP_ENCRYPTION_KEY
            echo
        fi
        
        DECRYPTED_FILE="${BACKUP_FILE%.enc}"
        
        openssl enc -aes-256-cbc -d \
            -in "$BACKUP_FILE_PATH" \
            -out "$BACKUP_PATH/$DECRYPTED_FILE" \
            -pass pass:"$BACKUP_ENCRYPTION_KEY"
        
        if [ $? -eq 0 ]; then
            BACKUP_FILE_PATH="$BACKUP_PATH/$DECRYPTED_FILE"
            TEMP_DECRYPTED=true
            log_success "Backup decrypted"
        else
            log_error "Failed to decrypt backup"
            exit 1
        fi
    fi
}

extract_backup() {
    log_info "Extracting backup..."
    
    # Use disk-backed path instead of /tmp (which may be tmpfs)
    RESTORE_TEMP="$BACKUP_PATH/.tmp/restore_$$"
    mkdir -p "$RESTORE_TEMP"
    
    cd "$RESTORE_TEMP"
    
    if [[ "$BACKUP_FILE_PATH" == *.tar.gz ]]; then
        tar -xzf "$BACKUP_FILE_PATH"
    elif [ -d "$BACKUP_FILE_PATH" ]; then
        cp -r "$BACKUP_FILE_PATH"/* .
    else
        log_error "Unknown backup format"
        exit 1
    fi
    
    # Find the extracted backup directory
    BACKUP_DIR=$(find . -maxdepth 1 -type d -name "archon_backup_*" | head -1)
    
    if [ -z "$BACKUP_DIR" ]; then
        log_error "Could not find backup directory in archive"
        exit 1
    fi
    
    log_success "Backup extracted to $RESTORE_TEMP/$BACKUP_DIR"
}

stop_services() {
    log_info "Stopping Archon services..."
    
    cd "$UNRAID_DIR"
    
    # Build compose args based on RUN_AS_ROOT setting
    COMPOSE_ARGS="-f docker-compose.unraid.yml"
    if [ "${RUN_AS_ROOT:-false}" != "true" ]; then
        COMPOSE_ARGS="$COMPOSE_ARGS -f docker-compose.override.yml"
    fi
    
    docker compose -p "${COMPOSE_PROJECT_NAME:-archon}" $COMPOSE_ARGS down
    
    # Wait for services to stop
    sleep 5
    
    log_success "Services stopped"
}

backup_current_data() {
    log_info "Creating safety backup of current data..."
    
    # Use disk-backed path instead of /tmp (which may be tmpfs)
    SAFETY_BACKUP="$BACKUP_PATH/.tmp/safety_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$SAFETY_BACKUP"
    
    # Backup current appdata
    if [ -d "$APPDATA_PATH" ]; then
        cp -r "$APPDATA_PATH" "$SAFETY_BACKUP/appdata_current"
    fi
    
    # Backup current data
    if [ -d "$DATA_PATH" ]; then
        cp -r "$DATA_PATH" "$SAFETY_BACKUP/data_current"
    fi
    
    # Preserve critical files that should be restored after the main restore
    mkdir -p "$SAFETY_BACKUP/preserve"
    log_info "Preserving critical configuration files..."
    
    for file in "${PRESERVE_FILES[@]}"; do
        if [ -f "$APPDATA_PATH/$file" ]; then
            cp "$APPDATA_PATH/$file" "$SAFETY_BACKUP/preserve/" 2>/dev/null && \
                log_info "  • Preserved: $file"
        elif [ -d "$APPDATA_PATH/$file" ]; then
            cp -r "$APPDATA_PATH/$file" "$SAFETY_BACKUP/preserve/" 2>/dev/null && \
                log_info "  • Preserved directory: $file"
        fi
    done
    
    log_success "Safety backup created at $SAFETY_BACKUP"
    echo "$SAFETY_BACKUP" > "$BACKUP_PATH/.tmp/safety_backup_path"
}

restore_appdata() {
    log_info "Restoring application data..."
    
    # Strict path safety guards
    APPDATA_REAL=$(realpath "$APPDATA_PATH")
    if [ -z "$APPDATA_REAL" ] || [ ! -d "$APPDATA_REAL" ] || [[ "$APPDATA_REAL" == "/" ]]; then
        log_error "Invalid APPDATA_PATH: '$APPDATA_REAL' - refusing to delete"
        exit 1
    fi
    
    # Ensure path is within expected Unraid appdata location
    if [[ "$APPDATA_REAL" != /mnt/user/appdata/archon* ]] && [[ "$APPDATA_REAL" != /mnt/cache/appdata/archon* ]]; then
        log_error "Unsafe APPDATA_PATH: $APPDATA_REAL - must be within /mnt/user/appdata/archon* or /mnt/cache/appdata/archon*"
        exit 1
    fi
    
    cd "$RESTORE_TEMP/$BACKUP_DIR"
    
    if [ -d "appdata" ]; then
        # Clear existing appdata (now safe after strict checks)
        rm -rf "$APPDATA_REAL"/*
        
        # Restore appdata
        cp -r appdata/* "$APPDATA_REAL/"
        
        # Set correct permissions
        if [ -f /etc/unraid-version ]; then
            PUID_VALUE=${PUID:-99}
            PGID_VALUE=${PGID:-100}
            chown -R "$PUID_VALUE:$PGID_VALUE" "$APPDATA_REAL"
        fi
        
        log_success "Application data restored"
    else
        log_warning "No application data found in backup"
    fi
}

restore_documents() {
    log_info "Restoring documents..."
    
    # Strict path safety guards
    DATA_REAL=$(realpath "$DATA_PATH")
    if [ -z "$DATA_REAL" ] || [ ! -d "$DATA_REAL" ] || [[ "$DATA_REAL" == "/" ]]; then
        log_error "Invalid DATA_PATH: '$DATA_REAL' - refusing to delete"
        exit 1
    fi
    
    # Ensure path is within expected data location
    if [[ "$DATA_REAL" != /mnt/user/archon-data* ]] && [[ "$DATA_REAL" != /mnt/cache/archon-data* ]]; then
        log_error "Unsafe DATA_PATH: $DATA_REAL - must be within /mnt/user/archon-data* or /mnt/cache/archon-data*"
        exit 1
    fi
    
    cd "$RESTORE_TEMP/$BACKUP_DIR"
    
    if [ -d "documents" ]; then
        # Clear existing documents (now safe after strict checks)
        rm -rf "$DATA_REAL"/*
        
        # Restore documents
        cp -r documents/* "$DATA_REAL/"
        
        # Set correct permissions
        if [ -f /etc/unraid-version ]; then
            PUID_VALUE=${PUID:-99}
            PGID_VALUE=${PGID:-100}
            chown -R "$PUID_VALUE:$PGID_VALUE" "$DATA_REAL"
        fi
        
        log_success "Documents restored"
    else
        log_warning "No documents found in backup"
    fi
}

restore_preserved_files() {
    log_info "Restoring preserved configuration files..."
    
    if [ -f "$BACKUP_PATH/.tmp/safety_backup_path" ]; then
        SAFETY_BACKUP=$(cat "$BACKUP_PATH/.tmp/safety_backup_path")
        
        if [ -d "$SAFETY_BACKUP/preserve" ]; then
            # Restore preserved files over the restored backup
            for file in "${PRESERVE_FILES[@]}"; do
                if [ -f "$SAFETY_BACKUP/preserve/$file" ]; then
                    cp "$SAFETY_BACKUP/preserve/$file" "$APPDATA_PATH/" 2>/dev/null && \
                        log_info "  • Restored preserved file: $file"
                elif [ -d "$SAFETY_BACKUP/preserve/$file" ]; then
                    cp -r "$SAFETY_BACKUP/preserve/$file" "$APPDATA_PATH/" 2>/dev/null && \
                        log_info "  • Restored preserved directory: $file"
                fi
            done
            
            log_success "Preserved files restored"
        else
            log_info "No preserved files to restore"
        fi
    else
        log_warning "No safety backup path found - skipping preserved file restoration"
    fi
}

restore_configuration() {
    log_info "Restoring configuration..."
    
    cd "$RESTORE_TEMP/$BACKUP_DIR"
    
    if [ -d "config" ]; then
        # Backup current .env file
        if [ -f "$UNRAID_DIR/.env" ]; then
            cp "$UNRAID_DIR/.env" "$UNRAID_DIR/.env.backup"
        fi
        
        # Restore configuration files (except sensitive data)
        if [ -f "config/env_sanitized.txt" ]; then
            log_info "Configuration template found (sensitive data must be re-entered)"
            
            # Merge with existing .env to preserve sensitive data
            if [ -f "$UNRAID_DIR/.env.backup" ]; then
                # Extract sensitive variables from backup
                TEMP_VARS="$BACKUP_PATH/.tmp/sensitive_vars_$$"
                grep -E "_KEY|_TOKEN|PASSWORD" "$UNRAID_DIR/.env.backup" > "$TEMP_VARS" || true
                
                # Combine sanitized config with sensitive vars
                cat "config/env_sanitized.txt" > "$UNRAID_DIR/.env"
                cat "$TEMP_VARS" >> "$UNRAID_DIR/.env"
                
                rm "$TEMP_VARS"
            fi
        fi
        
        # Restore docker-compose files if present
        if ls config/*.yml &>/dev/null; then
            cp config/*.yml "$UNRAID_DIR/"
        fi
        
        log_success "Configuration restored"
    else
        log_warning "No configuration found in backup"
    fi
}

restore_docker_images() {
    log_info "Checking for Docker images in backup..."
    
    cd "$RESTORE_TEMP/$BACKUP_DIR"
    
    if [ -d "images" ]; then
        log_info "Restoring Docker images..."
        
        for image_file in images/*.tar.gz; do
            if [ -f "$image_file" ]; then
                image_name=$(basename "$image_file" .tar.gz)
                log_info "Loading $image_name..."
                gunzip -c "$image_file" | docker load
            fi
        done
        
        log_success "Docker images restored"
    else
        log_info "No Docker images in backup, will pull from registry"
    fi
}

start_services() {
    log_info "Starting Archon services..."
    
    cd "$UNRAID_DIR"
    
    # Build compose args based on RUN_AS_ROOT setting
    COMPOSE_ARGS="-f docker-compose.unraid.yml"
    if [ "${RUN_AS_ROOT:-false}" != "true" ]; then
        COMPOSE_ARGS="$COMPOSE_ARGS -f docker-compose.override.yml"
    fi
    
    docker compose -p "${COMPOSE_PROJECT_NAME:-archon}" $COMPOSE_ARGS up -d
    
    # Wait for services to start
    sleep 10
    
    log_success "Services started"
}

verify_restoration() {
    log_info "Verifying restoration..."
    
    # Check service health
    services=("archon-server:8181" "archon-mcp:8051" "archon-agents:8052" "archon-frontend:3737")
    all_healthy=true
    
    for service in "${services[@]}"; do
        IFS=':' read -r name port <<< "$service"
        
        if docker ps | grep -q "$name"; then
            if curl -f -s "http://localhost:$port/health" > /dev/null 2>&1 || \
               curl -f -s "http://localhost:$port/" > /dev/null 2>&1; then
                log_success "$name is running and accessible"
            else
                log_warning "$name is running but health check failed"
                all_healthy=false
            fi
        else
            log_error "$name is not running"
            all_healthy=false
        fi
    done
    
    if [ "$all_healthy" = true ]; then
        log_success "All services restored and healthy"
        return 0
    else
        log_error "Some services failed to restore properly"
        return 1
    fi
}

rollback_restoration() {
    log_error "Restoration failed, rolling back..."
    
    stop_services
    
    # Restore from safety backup
    if [ -f "$BACKUP_PATH/.tmp/safety_backup_path" ]; then
        SAFETY_BACKUP=$(cat "$BACKUP_PATH/.tmp/safety_backup_path")
        
        if [ -d "$SAFETY_BACKUP" ]; then
            log_info "Restoring from safety backup..."
            
            # Restore appdata
            if [ -d "$SAFETY_BACKUP/appdata_current" ]; then
                rm -rf "$APPDATA_PATH"/*
                cp -r "$SAFETY_BACKUP/appdata_current"/* "$APPDATA_PATH/"
            fi
            
            # Restore data
            if [ -d "$SAFETY_BACKUP/data_current" ]; then
                rm -rf "$DATA_PATH"/*
                cp -r "$SAFETY_BACKUP/data_current"/* "$DATA_PATH/"
            fi
            
            start_services
            
            log_warning "Rolled back to previous state"
        fi
    fi
}

cleanup() {
    log_info "Cleaning up temporary files..."
    
    # Remove extraction directory
    if [ -n "$RESTORE_TEMP" ] && [ -d "$RESTORE_TEMP" ]; then
        rm -rf "$RESTORE_TEMP"
    fi
    
    # Remove decrypted backup if it was temporary
    if [ "$TEMP_DECRYPTED" = true ] && [ -n "$DECRYPTED_FILE" ]; then
        rm -f "$BACKUP_PATH/$DECRYPTED_FILE"
    fi
    
    # Remove safety backup path file
    rm -f "$BACKUP_PATH/.tmp/safety_backup_path"
    
    # Clean up entire .tmp directory if empty
    if [ -d "$BACKUP_PATH/.tmp" ]; then
        rmdir "$BACKUP_PATH/.tmp" 2>/dev/null || true
    fi
    
    log_success "Cleanup completed"
}

generate_restore_report() {
    log_info "Generating restore report..."
    
    REPORT_FILE="$BACKUP_PATH/restore_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$REPORT_FILE" <<EOF
=====================================
Archon Restore Report
=====================================
Timestamp: $(date)
Backup File: $BACKUP_FILE
Restore Status: SUCCESS

Restored Components:
- Application Data: Yes
- Documents: Yes
- Configuration: Yes
- Docker Images: $([ -d "$RESTORE_TEMP/$BACKUP_DIR/images" ] && echo "Yes" || echo "No")

Service Status:
$(docker ps --format "table {{.Names}}\t{{.Status}}" | grep archon)

Notes:
- Safety backup location: $(cat "$BACKUP_PATH/.tmp/safety_backup_path" 2>/dev/null || echo "N/A")
- Configuration may require re-entering sensitive data

=====================================
EOF
    
    log_success "Restore report generated: $REPORT_FILE"
}

# Main execution
main() {
    echo ""
    echo "========================================="
    echo "    Archon Restore Script"
    echo "========================================="
    echo ""
    
    # Enhanced confirmation process
    if [ "$2" != "--force" ]; then
        echo ""
        echo "🚨 DESTRUCTIVE OPERATION WARNING 🚨"
        echo "======================================"
        echo ""
        echo "This restore operation will:"
        echo "  • STOP all running Archon services"
        echo "  • DELETE all current application data in:"
        echo "    - $APPDATA_PATH"
        echo "    - $DATA_PATH"
        echo "  • REPLACE with backup data from:"
        echo "    - ${BACKUP_FILE:-[to be selected]}"
        echo ""
        echo "📋 Safety measures included:"
        echo "  • Current data will be backed up before deletion"
        echo "  • Backup will be preserved for recovery if needed"
        echo "  • Operation can be cancelled at any time"
        echo ""
        
        # Check if critical directories exist
        if [ -d "$APPDATA_PATH" ] && [ "$(ls -A "$APPDATA_PATH" 2>/dev/null)" ]; then
            echo "⚠️  EXISTING DATA DETECTED:"
            APPDATA_SIZE=$(du -sh "$APPDATA_PATH" 2>/dev/null | cut -f1 || echo "unknown")
            echo "  • AppData: $APPDATA_SIZE in $APPDATA_PATH"
        fi
        
        if [ -d "$DATA_PATH" ] && [ "$(ls -A "$DATA_PATH" 2>/dev/null)" ]; then
            DATA_SIZE=$(du -sh "$DATA_PATH" 2>/dev/null | cut -f1 || echo "unknown")
            echo "  • Documents: $DATA_SIZE in $DATA_PATH"
        fi
        
        echo ""
        echo "Type 'DELETE AND RESTORE' to confirm (case sensitive):"
        read -p "> " confirmation
        
        if [ "$confirmation" != "DELETE AND RESTORE" ]; then
            log_info "Restoration cancelled - confirmation text did not match"
            exit 0
        fi
        
        # Second confirmation for extra safety
        echo ""
        echo "Final confirmation - type 'yes' to proceed:"
        read -p "> " final_confirmation
        
        if [ "$final_confirmation" != "yes" ]; then
            log_info "Restoration cancelled at final confirmation"
            exit 0
        fi
        
        log_info "Destructive restore operation confirmed by user"
    else
        log_warning "Force mode enabled - skipping safety confirmations"
    fi
    
    # Start restoration process
    START_TIME=$(date +%s)
    
    select_backup
    verify_backup_integrity
    decrypt_backup
    extract_backup
    
    stop_services
    backup_current_data
    
    # Perform restoration
    restore_appdata
    restore_documents
    restore_configuration
    restore_preserved_files
    restore_docker_images
    
    start_services
    
    # Verify and finalize
    if verify_restoration; then
        generate_restore_report
        cleanup
        
        # Calculate duration
        END_TIME=$(date +%s)
        DURATION=$((END_TIME - START_TIME))
        DURATION_MIN=$((DURATION / 60))
        DURATION_SEC=$((DURATION % 60))
        
        log_success "Restoration completed successfully in ${DURATION_MIN}m ${DURATION_SEC}s"
        send_notification "Archon Restore Complete" "System restored successfully from backup" "normal"
        
        echo ""
        echo "IMPORTANT: Please verify the following:"
        echo "1. Check that all services are functioning correctly"
        echo "2. Re-enter any sensitive configuration (API keys, tokens)"
        echo "3. Test core functionality through the Web UI"
        echo ""
    else
        rollback_restoration
        cleanup
        
        log_error "Restoration failed and was rolled back"
        send_notification "Archon Restore Failed" "Restoration failed. System rolled back to previous state." "error"
        exit 1
    fi
}

# Handle script interruption
trap 'log_error "Restore interrupted"; rollback_restoration; cleanup; exit 1' INT TERM

# Run main function
main "$@"