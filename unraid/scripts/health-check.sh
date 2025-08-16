#!/bin/bash

# Archon Health Check Script for Unraid
# Comprehensive health monitoring with automated recovery

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
UNRAID_DIR="$PROJECT_ROOT/unraid"

# Load environment variables
if [ -f "$UNRAID_DIR/.env" ]; then
    source "$UNRAID_DIR/.env"
fi

# Health check configuration
HEALTH_CHECK_INTERVAL="${HEALTH_CHECK_INTERVAL:-30}"
HEALTH_CHECK_TIMEOUT="${HEALTH_CHECK_TIMEOUT:-10}"
HEALTH_CHECK_RETRIES="${HEALTH_CHECK_RETRIES:-3}"
AUTO_RECOVERY="${AUTO_RECOVERY:-true}"
ALERT_ON_FAILURE="${ALERT_ON_FAILURE:-true}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check mode
CHECK_MODE="${1:-comprehensive}"

# Service configuration
declare -A SERVICES=(
    ["archon-server"]="8181:/health"
    ["archon-mcp"]="8051:/health"
    ["archon-agents"]="8052:/health"
    ["archon-frontend"]="3737:/"
)

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
    logger -t "archon-health" "$1" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    logger -t "archon-health" "SUCCESS: $1" 2>/dev/null || true
}

log_warning() {
    echo -e "${YELLOW}[⚠]${NC} $1"
    logger -t "archon-health" "WARNING: $1" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
    logger -t "archon-health" "ERROR: $1" 2>/dev/null || true
}

log_metric() {
    echo -e "${CYAN}[📊]${NC} $1"
}

send_notification() {
    local subject="$1"
    local message="$2"
    local importance="${3:-normal}"
    
    if [ "$ALERT_ON_FAILURE" == "true" ] && command -v notify &> /dev/null; then
        notify -s "$subject" -d "$message" -i "$importance"
    fi
}

check_container_status() {
    local container="$1"
    local port_endpoint="$2"
    
    IFS=':' read -r port endpoint <<< "$port_endpoint"
    
    # Check if container is running
    if ! docker ps --format '{{.Names}}' | grep -q "^$container$"; then
        log_error "$container is not running"
        return 1
    fi
    
    # Check container state
    state=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null)
    if [ "$state" != "running" ]; then
        log_error "$container state: $state"
        return 1
    fi
    
    # Check health status if available
    health_status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "none")
    
    if [ "$health_status" == "unhealthy" ]; then
        log_warning "$container health status: unhealthy"
        return 1
    fi
    
    # Check HTTP endpoint
    url="http://localhost:$port$endpoint"
    response_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$HEALTH_CHECK_TIMEOUT" "$url" 2>/dev/null)
    
    if [ "$response_code" == "200" ] || [ "$response_code" == "204" ]; then
        response_time=$(curl -s -o /dev/null -w "%{time_total}" "$url" 2>/dev/null)
        log_success "$container is healthy (response: ${response_code}, time: ${response_time}s)"
        return 0
    else
        log_error "$container endpoint returned $response_code"
        return 1
    fi
}

check_resource_usage() {
    local container="$1"
    
    if ! docker ps --format '{{.Names}}' | grep -q "^$container$"; then
        return 1
    fi
    
    # Get container stats
    stats=$(docker stats --no-stream --format "{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" "$container" 2>/dev/null)
    
    if [ -n "$stats" ]; then
        IFS=$'\t' read -r cpu mem net block <<< "$stats"
        
        # Extract CPU percentage
        cpu_percent=$(echo "$cpu" | sed 's/%//')
        
        # Check for high CPU usage
        if (( $(echo "$cpu_percent > 80" | bc -l 2>/dev/null || echo 0) )); then
            log_warning "$container CPU usage is high: $cpu"
        fi
        
        log_metric "$container - CPU: $cpu, Memory: $mem, Network: $net, Disk: $block"
    fi
}

check_disk_space() {
    local path="$1"
    local min_space_gb="${2:-1}"
    
    if [ -d "$path" ]; then
        available_gb=$(df "$path" | awk 'NR==2 {print int($4/1048576)}')
        used_percent=$(df "$path" | awk 'NR==2 {print $5}' | sed 's/%//')
        
        if [ "$available_gb" -lt "$min_space_gb" ]; then
            log_error "Low disk space at $path: ${available_gb}GB available"
            return 1
        fi
        
        if [ "$used_percent" -gt 90 ]; then
            log_warning "High disk usage at $path: ${used_percent}%"
        fi
        
        log_metric "Disk usage for $path: ${used_percent}% used, ${available_gb}GB free"
    fi
    
    return 0
}

check_network_connectivity() {
    local container="$1"
    
    # Check if container can resolve DNS
    if docker exec "$container" nslookup google.com &>/dev/null; then
        log_success "$container has DNS connectivity"
    else
        log_warning "$container cannot resolve DNS"
    fi
    
    # Check inter-container connectivity
    for target in "${!SERVICES[@]}"; do
        if [ "$target" != "$container" ]; then
            if docker exec "$container" ping -c 1 "$target" &>/dev/null; then
                log_success "$container can reach $target"
            else
                log_warning "$container cannot reach $target"
            fi
        fi
    done
}

check_logs_for_errors() {
    local container="$1"
    local error_count=0
    
    # Check for recent errors in container logs
    recent_errors=$(docker logs --since 5m "$container" 2>&1 | grep -iE "error|exception|fatal|panic" | wc -l)
    
    if [ "$recent_errors" -gt 0 ]; then
        log_warning "$container has $recent_errors errors in recent logs"
        
        # Show last few errors
        echo "Recent errors from $container:"
        docker logs --since 5m "$container" 2>&1 | grep -iE "error|exception|fatal|panic" | tail -3
    else
        log_success "$container has no recent errors"
    fi
    
    return 0
}

attempt_recovery() {
    local container="$1"
    local attempts=0
    local max_attempts=3
    
    log_info "Attempting to recover $container..."
    
    while [ $attempts -lt $max_attempts ]; do
        attempts=$((attempts + 1))
        log_info "Recovery attempt $attempts/$max_attempts for $container"
        
        # Try restart first
        docker restart "$container"
        sleep 10
        
        # Check if recovery was successful
        if check_container_status "$container" "${SERVICES[$container]}"; then
            log_success "$container recovered successfully"
            send_notification "Archon Service Recovered" "$container has been recovered successfully" "normal"
            return 0
        fi
        
        if [ $attempts -lt $max_attempts ]; then
            # Try more aggressive recovery
            log_info "Attempting force recreation of $container..."
            
            cd "$UNRAID_DIR"
            docker compose -f docker-compose.unraid.yml up -d --force-recreate "$container"
            sleep 15
        fi
    done
    
    log_error "Failed to recover $container after $max_attempts attempts"
    send_notification "Archon Service Failed" "$container could not be recovered" "error"
    return 1
}

comprehensive_check() {
    local overall_health="healthy"
    local failed_services=""
    
    echo "======================================"
    echo "   Archon Comprehensive Health Check"
    echo "======================================"
    echo ""
    
    # Check each service
    for container in "${!SERVICES[@]}"; do
        echo "Checking $container..."
        echo "------------------------"
        
        if check_container_status "$container" "${SERVICES[$container]}"; then
            check_resource_usage "$container"
            check_logs_for_errors "$container"
        else
            overall_health="unhealthy"
            failed_services="$failed_services $container"
            
            if [ "$AUTO_RECOVERY" == "true" ]; then
                attempt_recovery "$container"
            fi
        fi
        
        echo ""
    done
    
    # Check disk space
    echo "System Resources"
    echo "------------------------"
    check_disk_space "${APPDATA_PATH:-/mnt/user/appdata/archon}" 1
    check_disk_space "${DATA_PATH:-/mnt/user/archon-data}" 1
    check_disk_space "/var/lib/docker" 5
    
    echo ""
    echo "======================================"
    
    if [ "$overall_health" == "healthy" ]; then
        log_success "All systems operational"
        return 0
    else
        log_error "Health check failed for:$failed_services"
        return 1
    fi
}

quick_check() {
    local all_healthy=true
    
    echo "Quick Health Status:"
    echo "-------------------"
    
    for container in "${!SERVICES[@]}"; do
        port_endpoint="${SERVICES[$container]}"
        IFS=':' read -r port endpoint <<< "$port_endpoint"
        
        if docker ps --format '{{.Names}}' | grep -q "^$container$"; then
            response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost:$port$endpoint" 2>/dev/null)
            
            if [ "$response" == "200" ] || [ "$response" == "204" ]; then
                echo -e "${GREEN}✓${NC} $container"
            else
                echo -e "${RED}✗${NC} $container (HTTP $response)"
                all_healthy=false
            fi
        else
            echo -e "${RED}✗${NC} $container (not running)"
            all_healthy=false
        fi
    done
    
    if [ "$all_healthy" = true ]; then
        return 0
    else
        return 1
    fi
}

continuous_monitoring() {
    log_info "Starting continuous health monitoring (interval: ${HEALTH_CHECK_INTERVAL}s)"
    
    while true; do
        clear
        echo "======================================"
        echo "  Archon Health Monitor - $(date '+%Y-%m-%d %H:%M:%S')"
        echo "======================================"
        echo ""
        
        if quick_check; then
            echo ""
            log_success "All services healthy"
        else
            echo ""
            log_warning "Some services need attention"
            
            if [ "$AUTO_RECOVERY" == "true" ]; then
                for container in "${!SERVICES[@]}"; do
                    if ! check_container_status "$container" "${SERVICES[$container]}" &>/dev/null; then
                        attempt_recovery "$container"
                    fi
                done
            fi
        fi
        
        echo ""
        echo "Next check in ${HEALTH_CHECK_INTERVAL} seconds... (Press Ctrl+C to stop)"
        sleep "$HEALTH_CHECK_INTERVAL"
    done
}

generate_health_report() {
    local report_file="${APPDATA_PATH:-/mnt/user/appdata/archon}/logs/health_$(date +%Y%m%d_%H%M%S).json"
    
    log_info "Generating health report..."
    
    # Generate JSON report
    {
        echo "{"
        echo "  \"timestamp\": \"$(date -Iseconds)\","
        echo "  \"services\": {"
        
        first=true
        for container in "${!SERVICES[@]}"; do
            if [ "$first" = false ]; then echo ","; fi
            first=false
            
            status="down"
            if docker ps --format '{{.Names}}' | grep -q "^$container$"; then
                status="running"
                
                port_endpoint="${SERVICES[$container]}"
                IFS=':' read -r port endpoint <<< "$port_endpoint"
                
                response=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 2 "http://localhost:$port$endpoint" 2>/dev/null)
                if [ "$response" == "200" ] || [ "$response" == "204" ]; then
                    status="healthy"
                fi
            fi
            
            echo -n "    \"$container\": {"
            echo -n "\"status\": \"$status\""
            
            if [ "$status" != "down" ]; then
                stats=$(docker stats --no-stream --format '{"cpu":"{{.CPUPerc}}","memory":"{{.MemUsage}}"}' "$container" 2>/dev/null)
                if [ -n "$stats" ]; then
                    echo -n ", \"stats\": $stats"
                fi
            fi
            
            echo -n "}"
        done
        
        echo ""
        echo "  },"
        echo "  \"disk\": {"
        echo "    \"appdata\": \"$(df -h "${APPDATA_PATH:-/mnt/user/appdata/archon}" 2>/dev/null | awk 'NR==2 {print $5}')\","
        echo "    \"data\": \"$(df -h "${DATA_PATH:-/mnt/user/archon-data}" 2>/dev/null | awk 'NR==2 {print $5}')\""
        echo "  }"
        echo "}"
    } > "$report_file"
    
    log_success "Health report saved to $report_file"
}

# Main execution
main() {
    # Check tool availability first
    check_tools
    
    case "$CHECK_MODE" in
        "comprehensive"|"full")
            comprehensive_check
            generate_health_report
            ;;
        "quick")
            quick_check
            ;;
        "monitor"|"continuous")
            continuous_monitoring
            ;;
        "report")
            generate_health_report
            ;;
        *)
            echo "Usage: $0 [comprehensive|quick|monitor|report]"
            echo ""
            echo "Modes:"
            echo "  comprehensive - Full health check with recovery attempts"
            echo "  quick        - Quick status check"
            echo "  monitor      - Continuous monitoring"
            echo "  report       - Generate health report"
            exit 1
            ;;
    esac
}

# Handle script interruption
trap 'echo ""; log_info "Health check stopped"; exit 0' INT TERM

# Run main function
main "$@"