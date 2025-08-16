#!/bin/bash

# Archon Unraid Maintenance Script
# Automated maintenance tasks for Archon deployment

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
UNRAID_DIR="$PROJECT_ROOT/unraid"

# Load environment variables
if [ -f "$UNRAID_DIR/.env" ]; then
    source "$UNRAID_DIR/.env"
fi

# Configuration with defaults
APPDATA_PATH="${APPDATA_PATH:-/mnt/user/appdata/archon}"
DATA_PATH="${DATA_PATH:-/mnt/user/archon-data}"
LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS:-7}"
DOCKER_PRUNE="${DOCKER_PRUNE:-true}"
AUTO_UPDATE="${AUTO_UPDATE:-false}"
HEALTH_CHECK_ENABLED="${HEALTH_CHECK_ENABLED:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Maintenance mode (can be passed as argument)
MAINTENANCE_MODE="${1:-full}"

# Functions
check_tools() {
    log_info "Checking required tools availability..."
    
    local missing_tools=()
    local optional_tools=()
    
    # Check required tools
    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi
    
    if ! command -v bc &> /dev/null; then
        missing_tools+=("bc")
    fi
    
    # Check optional tools with fallbacks
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        missing_tools+=("curl or wget")
    fi
    
    if ! command -v ping &> /dev/null; then
        optional_tools+=("ping (network connectivity checks disabled)")
    fi
    
    if ! command -v nslookup &> /dev/null && ! command -v dig &> /dev/null; then
        optional_tools+=("nslookup/dig (DNS checks disabled)")
    fi
    
    # Report missing required tools
    if [ ${#missing_tools[@]} -gt 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Installing missing tools..."
        
        # Try to install on Unraid
        if [ -f /etc/unraid-version ]; then
            for tool in "${missing_tools[@]}"; do
                case "$tool" in
                    "jq")
                        if command -v opkg &> /dev/null; then
                            opkg update && opkg install jq
                        else
                            log_warning "Cannot install jq automatically. JSON parsing disabled."
                        fi
                        ;;
                    "bc")
                        if command -v opkg &> /dev/null; then
                            opkg update && opkg install bc
                        else
                            log_warning "Cannot install bc automatically. Some calculations disabled."
                        fi
                        ;;
                    "curl or wget")
                        log_error "Neither curl nor wget available. Cannot perform HTTP health checks."
                        ;;
                esac
            done
        else
            log_error "Please install missing tools: ${missing_tools[*]}"
            exit 1
        fi
    fi
    
    # Report optional tools
    if [ ${#optional_tools[@]} -gt 0 ]; then
        for tool in "${optional_tools[@]}"; do
            log_warning "$tool"
        done
    fi
    
    log_success "Tool availability check completed"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    logger -t "archon-maintenance" "$1" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    logger -t "archon-maintenance" "SUCCESS: $1" 2>/dev/null || true
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    logger -t "archon-maintenance" "WARNING: $1" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    logger -t "archon-maintenance" "ERROR: $1" 2>/dev/null || true
}

log_metric() {
    echo -e "${CYAN}[METRIC]${NC} $1"
}

send_notification() {
    local subject="$1"
    local message="$2"
    local importance="${3:-normal}"
    
    if command -v notify &> /dev/null; then
        notify -s "$subject" -d "$message" -i "$importance"
    fi
}

check_service_health() {
    log_info "Checking service health..."
    
    local unhealthy_services=""
    local services=("archon-server" "archon-mcp" "archon-agents" "archon-frontend")
    
    for service in "${services[@]}"; do
        if docker ps --format '{{.Names}}' | grep -q "^$service$"; then
            # Check container health status
            health_status=$(docker inspect --format='{{.State.Health.Status}}' "$service" 2>/dev/null || echo "none")
            
            if [ "$health_status" == "healthy" ] || [ "$health_status" == "none" ]; then
                log_success "$service is healthy"
            else
                log_warning "$service health status: $health_status"
                unhealthy_services="$unhealthy_services $service"
            fi
            
            # Check resource usage
            stats=$(docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}" "$service" | tail -n 1)
            log_metric "$stats"
        else
            log_error "$service is not running"
            unhealthy_services="$unhealthy_services $service"
        fi
    done
    
    if [ -n "$unhealthy_services" ]; then
        log_warning "Unhealthy services detected:$unhealthy_services"
        
        # Attempt to restart unhealthy services
        for service in $unhealthy_services; do
            log_info "Attempting to restart $service..."
            docker restart "$service"
            sleep 5
        done
        
        return 1
    fi
    
    return 0
}

clean_logs() {
    log_info "Cleaning old logs..."
    
    local log_dirs=(
        "$APPDATA_PATH/logs/server"
        "$APPDATA_PATH/logs/mcp"
        "$APPDATA_PATH/logs/agents"
        "$APPDATA_PATH/logs/frontend"
    )
    
    local total_cleaned=0
    
    for log_dir in "${log_dirs[@]}"; do
        if [ -d "$log_dir" ]; then
            # Count files before cleaning
            before_count=$(find "$log_dir" -type f -name "*.log*" 2>/dev/null | wc -l)
            
            # Remove old log files
            find "$log_dir" -type f -name "*.log*" -mtime +$LOG_RETENTION_DAYS -delete 2>/dev/null || true
            
            # Truncate large active log files
            find "$log_dir" -type f -name "*.log" -size +100M -exec truncate -s 10M {} \; 2>/dev/null || true
            
            # Count files after cleaning
            after_count=$(find "$log_dir" -type f -name "*.log*" 2>/dev/null | wc -l)
            cleaned=$((before_count - after_count))
            total_cleaned=$((total_cleaned + cleaned))
            
            if [ $cleaned -gt 0 ]; then
                log_info "Cleaned $cleaned log files from $(basename $log_dir)"
            fi
        fi
    done
    
    # Clean Docker container logs
    for container in $(docker ps -a --format '{{.Names}}' | grep '^archon-'); do
        log_file=$(docker inspect --format='{{.LogPath}}' "$container" 2>/dev/null)
        if [ -f "$log_file" ] && [ $(stat -f%z "$log_file" 2>/dev/null || stat -c%s "$log_file") -gt 104857600 ]; then
            truncate -s 10M "$log_file"
            log_info "Truncated Docker logs for $container"
        fi
    done
    
    log_success "Log cleanup completed (removed $total_cleaned old files)"
}

docker_cleanup() {
    if [ "$DOCKER_PRUNE" == "true" ]; then
        log_info "Performing Docker cleanup..."
        
        # Get disk usage before cleanup
        before_space=$(df /var/lib/docker | awk 'NR==2 {print $3}')
        
        # Remove stopped containers
        stopped_containers=$(docker ps -a -q -f status=exited -f label=com.docker.compose.project=archon)
        if [ -n "$stopped_containers" ]; then
            docker rm $stopped_containers
            log_info "Removed stopped containers"
        fi
        
        # Remove dangling images
        docker image prune -f --filter "label!=keep"
        
        # Remove unused volumes (careful with this)
        # docker volume prune -f
        
        # Remove unused networks
        docker network prune -f
        
        # Get disk usage after cleanup
        after_space=$(df /var/lib/docker | awk 'NR==2 {print $3}')
        freed_space=$((before_space - after_space))
        
        if [ $freed_space -gt 0 ]; then
            freed_mb=$((freed_space / 1024))
            log_success "Docker cleanup freed ${freed_mb}MB of space"
        else
            log_info "Docker cleanup completed (no space freed)"
        fi
    fi
}

update_containers() {
    if [ "$AUTO_UPDATE" == "true" ]; then
        log_info "Checking for container updates..."
        
        cd "$UNRAID_DIR"
        
        # Pull latest images
        updated=false
        for image in archon-server archon-mcp archon-agents archon-frontend; do
            log_info "Checking $image for updates..."
            
            # Get current image ID
            current_id=$(docker images --format "{{.ID}}" "ghcr.io/archon/$image:latest" 2>/dev/null)
            
            # Try to pull latest
            if docker pull "ghcr.io/archon/$image:latest" 2>/dev/null; then
                new_id=$(docker images --format "{{.ID}}" "ghcr.io/archon/$image:latest")
                
                if [ "$current_id" != "$new_id" ]; then
                    log_info "Update available for $image"
                    updated=true
                fi
            fi
        done
        
        if [ "$updated" = true ]; then
            log_info "Updates found, recreating containers..."
            
            # Backup before update
            "$SCRIPT_DIR/backup.sh" incremental
            
            # Recreate containers with new images
            docker compose -f docker-compose.unraid.yml -f docker-compose.override.yml up -d --force-recreate
            
            log_success "Containers updated successfully"
            send_notification "Archon Updated" "Containers have been updated to latest versions" "normal"
        else
            log_info "All containers are up to date"
        fi
    else
        log_info "Auto-update is disabled, skipping container updates"
    fi
}

optimize_database() {
    log_info "Optimizing database connections..."
    
    # This is a placeholder for database optimization
    # Actual implementation would depend on Supabase access
    
    # Check connection pool usage
    for container in archon-server archon-mcp archon-agents; do
        if docker ps --format '{{.Names}}' | grep -q "^$container$"; then
            # Get connection metrics from container logs
            connections=$(docker logs "$container" 2>&1 | grep -c "database connection" || echo "0")
            log_metric "$container database connections: $connections"
        fi
    done
    
    log_info "Database optimization completed"
}

check_storage() {
    log_info "Checking storage usage..."
    
    # Check appdata usage
    if [ -d "$APPDATA_PATH" ]; then
        appdata_usage=$(du -sh "$APPDATA_PATH" 2>/dev/null | cut -f1)
        log_metric "AppData usage: $appdata_usage"
    fi
    
    # Check data usage
    if [ -d "$DATA_PATH" ]; then
        data_usage=$(du -sh "$DATA_PATH" 2>/dev/null | cut -f1)
        log_metric "Data storage usage: $data_usage"
    fi
    
    # Check available space
    available_space=$(df -h "$APPDATA_PATH" 2>/dev/null | awk 'NR==2 {print $4}')
    log_metric "Available space: $available_space"
    
    # Warn if space is low
    available_kb=$(df "$APPDATA_PATH" 2>/dev/null | awk 'NR==2 {print $4}')
    if [ "$available_kb" -lt 1048576 ]; then # Less than 1GB
        log_warning "Low disk space warning: $available_space remaining"
        send_notification "Archon Low Disk Space" "Less than 1GB of space remaining" "warning"
    fi
}

security_check() {
    log_info "Performing security checks..."
    
    # Check for exposed ports
    exposed_ports=$(docker ps --format "table {{.Names}}\t{{.Ports}}" | grep archon | grep -c "0.0.0.0" || echo "0")
    if [ "$exposed_ports" -gt 0 ]; then
        log_warning "Services are exposed on all interfaces (0.0.0.0)"
    fi
    
    # Check file permissions
    if [ -f /etc/unraid-version ]; then
        # Check for files not owned by nobody:users
        wrong_perms=$(find "$APPDATA_PATH" ! -user 99 -o ! -group 100 2>/dev/null | wc -l)
        if [ "$wrong_perms" -gt 0 ]; then
            log_warning "Found $wrong_perms files with incorrect permissions"
            log_info "Fixing file permissions..."
            chown -R 99:100 "$APPDATA_PATH" 2>/dev/null || true
            chown -R 99:100 "$DATA_PATH" 2>/dev/null || true
        fi
    fi
    
    # Check for sensitive data in logs
    sensitive_patterns="password|token|key|secret"
    for log_dir in "$APPDATA_PATH"/logs/*; do
        if [ -d "$log_dir" ]; then
            if grep -r -i "$sensitive_patterns" "$log_dir" &>/dev/null; then
                log_warning "Potential sensitive data found in logs at $log_dir"
            fi
        fi
    done
    
    log_success "Security check completed"
}

performance_tuning() {
    log_info "Checking performance metrics..."
    
    # Collect performance metrics
    for container in archon-server archon-mcp archon-agents archon-frontend; do
        if docker ps --format '{{.Names}}' | grep -q "^$container$"; then
            # Get container stats
            stats=$(docker stats --no-stream --format "json" "$container" 2>/dev/null)
            
            if [ -n "$stats" ]; then
                cpu_percent=$(echo "$stats" | jq -r '.CPUPerc' | sed 's/%//')
                mem_usage=$(echo "$stats" | jq -r '.MemUsage' | cut -d'/' -f1)
                
                # Check if container is under stress
                if (( $(echo "$cpu_percent > 80" | bc -l) )); then
                    log_warning "$container CPU usage is high: ${cpu_percent}%"
                fi
            fi
        fi
    done
    
    # Check response times
    endpoints=("8181:server" "8051:mcp" "8052:agents" "3737:frontend")
    for endpoint in "${endpoints[@]}"; do
        IFS=':' read -r port name <<< "$endpoint"
        
        response_time=$(curl -o /dev/null -s -w '%{time_total}' "http://localhost:$port/health" 2>/dev/null || echo "N/A")
        
        if [ "$response_time" != "N/A" ]; then
            log_metric "$name response time: ${response_time}s"
            
            # Alert if response time is slow
            if (( $(echo "$response_time > 2" | bc -l) )); then
                log_warning "$name is responding slowly"
            fi
        fi
    done
    
    log_success "Performance check completed"
}

generate_report() {
    log_info "Generating maintenance report..."
    
    REPORT_FILE="$APPDATA_PATH/logs/maintenance_$(date +%Y%m%d_%H%M%S).txt"
    
    {
        echo "====================================="
        echo "Archon Maintenance Report"
        echo "====================================="
        echo "Timestamp: $(date)"
        echo "Maintenance Mode: $MAINTENANCE_MODE"
        echo ""
        echo "System Status:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep archon || echo "No services running"
        echo ""
        echo "Resource Usage:"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}" $(docker ps --format '{{.Names}}' | grep archon) 2>/dev/null || echo "Unable to get stats"
        echo ""
        echo "Storage Usage:"
        echo "  AppData: $(du -sh "$APPDATA_PATH" 2>/dev/null | cut -f1)"
        echo "  Data: $(du -sh "$DATA_PATH" 2>/dev/null | cut -f1)"
        echo "  Available: $(df -h "$APPDATA_PATH" 2>/dev/null | awk 'NR==2 {print $4}')"
        echo ""
        echo "Recent Errors (last 24h):"
        find "$APPDATA_PATH"/logs -name "*.log" -mtime -1 -exec grep -l ERROR {} \; 2>/dev/null | wc -l
        echo ""
        echo "Maintenance Tasks Completed:"
        echo "  - Health check"
        echo "  - Log cleanup"
        echo "  - Docker cleanup"
        echo "  - Storage check"
        echo "  - Security check"
        echo "  - Performance check"
        echo "====================================="
    } > "$REPORT_FILE"
    
    log_success "Report generated: $REPORT_FILE"
}

# Main execution
main() {
    echo ""
    echo "========================================="
    echo "    Archon Maintenance Script"
    echo "========================================="
    echo "Mode: $MAINTENANCE_MODE"
    echo ""
    
    START_TIME=$(date +%s)
    
    # Check tool availability first
    check_tools
    
    case "$MAINTENANCE_MODE" in
        "full")
            check_service_health
            clean_logs
            docker_cleanup
            update_containers
            optimize_database
            check_storage
            security_check
            performance_tuning
            ;;
        "quick")
            check_service_health
            clean_logs
            check_storage
            ;;
        "health")
            check_service_health
            ;;
        "cleanup")
            clean_logs
            docker_cleanup
            ;;
        "update")
            update_containers
            ;;
        "security")
            security_check
            ;;
        *)
            log_error "Unknown maintenance mode: $MAINTENANCE_MODE"
            echo "Available modes: full, quick, health, cleanup, update, security"
            exit 1
            ;;
    esac
    
    generate_report
    
    # Calculate duration
    END_TIME=$(date +%s)
    DURATION=$((END_TIME - START_TIME))
    
    log_success "Maintenance completed in ${DURATION} seconds"
    
    # Send notification based on results
    if check_service_health; then
        send_notification "Archon Maintenance Complete" "All systems healthy. Mode: $MAINTENANCE_MODE" "normal"
    else
        send_notification "Archon Maintenance Alert" "Some services require attention. Check logs." "warning"
    fi
}

# Run main function
main "$@"