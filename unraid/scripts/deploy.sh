#!/bin/bash

# Archon Unraid Deployment Script
# Automates the deployment of Archon stack on Unraid

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
UNRAID_DIR="$PROJECT_ROOT/unraid"

# Default paths (will be overridden by .env if present)
APPDATA_BASE="/mnt/user/appdata/archon"
DATA_BASE="/mnt/user/archon-data"
BACKUP_BASE="/mnt/user/backups/archon"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

detect_curl_bash_execution() {
    # Detect if script is being executed from stdin (curl | bash)
    if [ ! -t 0 ] && { [ -z "$UNRAID_DIR" ] || [ ! -d "$UNRAID_DIR" ]; }; then
        log_info "Detected curl | bash execution, cloning repository..."
        
        # Default installation directory
        INSTALL_DIR="/mnt/user/appdata/archon"
        
        # Create installation directory
        mkdir -p "$INSTALL_DIR"
        cd "$INSTALL_DIR"
        
        # Use pinned release version for security (fallback to main if not available)
        RELEASE_VERSION="${ARCHON_RELEASE_VERSION:-main}"
        
        # Clone the repository - with fallback to zip download
        if command -v git &> /dev/null; then
            if [ "$RELEASE_VERSION" != "main" ]; then
                log_info "Cloning Archon release $RELEASE_VERSION for security..."
                git clone --branch "$RELEASE_VERSION" --depth 1 https://github.com/coleam00/Archon.git . || {
                    log_warning "Release $RELEASE_VERSION not found, falling back to main branch"
                    git clone --depth 1 https://github.com/coleam00/Archon.git .
                }
            else
                log_warning "Using main branch (not recommended for production)"
                log_warning "Set ARCHON_RELEASE_VERSION=v1.0.0 in environment for pinned release"
                git clone --depth 1 https://github.com/coleam00/Archon.git .
            fi
        else
            log_info "Git not found; downloading zip archive..."
            if command -v curl &> /dev/null; then
                if [ "$RELEASE_VERSION" != "main" ]; then
                    log_info "Downloading Archon release $RELEASE_VERSION..."
                    curl -L -o archon.zip "https://github.com/coleam00/Archon/archive/refs/tags/${RELEASE_VERSION}.zip" || {
                        log_warning "Release $RELEASE_VERSION not found, falling back to main"
                        curl -L -o archon.zip https://github.com/coleam00/Archon/archive/refs/heads/main.zip
                    }
                else
                    log_warning "Downloading from main branch (not recommended for production)"
                    curl -L -o archon.zip https://github.com/coleam00/Archon/archive/refs/heads/main.zip
                fi
            elif command -v wget &> /dev/null; then
                if [ "$RELEASE_VERSION" != "main" ]; then
                    log_info "Downloading Archon release $RELEASE_VERSION..."
                    wget -O archon.zip "https://github.com/coleam00/Archon/archive/refs/tags/${RELEASE_VERSION}.zip" || {
                        log_warning "Release $RELEASE_VERSION not found, falling back to main"
                        wget -O archon.zip https://github.com/coleam00/Archon/archive/refs/heads/main.zip
                    }
                else
                    log_warning "Downloading from main branch (not recommended for production)"
                    wget -O archon.zip https://github.com/coleam00/Archon/archive/refs/heads/main.zip
                fi
            else
                log_error "Neither git, curl, nor wget is available. Cannot download repository."
                exit 1
            fi
            
            # Extract archive
            if command -v unzip &> /dev/null; then
                unzip -q archon.zip
                # Handle both main branch and versioned releases with case-insensitive matching
                shopt -s nocaseglob
                
                # Check for main branch (case-insensitive)
                main_dirs=(archon-main Archon-main)
                found_main=""
                for dir in "${main_dirs[@]}"; do
                    if [ -d "$dir" ]; then
                        found_main="$dir"
                        break
                    fi
                done
                
                if [ -n "$found_main" ]; then
                    mv "$found_main"/* .
                    rm -rf "$found_main"
                elif [ -n "$RELEASE_VERSION" ]; then
                    # Check for versioned releases (case-insensitive)
                    version_dirs=("archon-${RELEASE_VERSION#v}" "Archon-${RELEASE_VERSION#v}")
                    found_version=""
                    for dir in "${version_dirs[@]}"; do
                        if [ -d "$dir" ]; then
                            found_version="$dir"
                            break
                        fi
                    done
                    
                    if [ -n "$found_version" ]; then
                        mv "$found_version"/* .
                        rm -rf "$found_version"
                    else
                        # Find any extracted directory using case-insensitive pattern
                        extracted_dir=$(find . -maxdepth 1 -type d -iname "archon-*" | head -1)
                        if [ -n "$extracted_dir" ]; then
                            mv "$extracted_dir"/* .
                            rm -rf "$extracted_dir"
                        fi
                    fi
                else
                    # Find any extracted directory using case-insensitive pattern
                    extracted_dir=$(find . -maxdepth 1 -type d -iname "archon-*" | head -1)
                    if [ -n "$extracted_dir" ]; then
                        mv "$extracted_dir"/* .
                        rm -rf "$extracted_dir"
                    fi
                fi
                
                shopt -u nocaseglob
                rm -f archon.zip
            else
                log_error "unzip is not available. Cannot extract repository."
                exit 1
            fi
        fi
        
        # Update paths to point to cloned repository
        PROJECT_ROOT="$INSTALL_DIR"
        UNRAID_DIR="$INSTALL_DIR/unraid"
        
        log_success "Repository installed to $INSTALL_DIR"
    fi
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Detect and handle curl | bash execution
    detect_curl_bash_execution
    
    # Check if running on Unraid
    if [ ! -f /etc/unraid-version ]; then
        log_warning "This script is optimized for Unraid but running on a different system"
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check Docker Compose
    if ! docker compose version &>/dev/null; then
        if command -v docker-compose &>/dev/null; then
            export DOCKER_COMPOSE_BIN="docker-compose"
            log_warning "Using docker-compose (v1) instead of Docker Compose plugin (v2)"
        else
            log_error "Docker Compose (v2 plugin or docker-compose) not installed"
            exit 1
        fi
    else
        export DOCKER_COMPOSE_BIN="docker compose"
    fi
    
    # Check for curl or wget for HTTP verification
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        log_warning "Neither curl nor wget is available. HTTP verification will be skipped."
        HTTP_CHECK_AVAILABLE=false
    else
        HTTP_CHECK_AVAILABLE=true
    fi
    
    # Load environment variables to get custom paths
    if [ -f "$UNRAID_DIR/.env" ]; then
        source "$UNRAID_DIR/.env"
    fi
    
    # Update paths from environment variables
    APPDATA_BASE="${APPDATA_PATH:-$APPDATA_BASE}"
    DATA_BASE="${DATA_PATH:-$DATA_BASE}"
    BACKUP_BASE="${BACKUP_PATH:-$BACKUP_BASE}"
    
    # Export for docker-compose
    export APPDATA_PATH="$APPDATA_BASE"
    export DATA_PATH="$DATA_BASE"
    
    # Check for required directories
    if [ ! -d "/mnt/user" ]; then
        log_warning "/mnt/user not found. Using local directories instead."
        APPDATA_BASE="$HOME/appdata/archon"
        DATA_BASE="$HOME/archon-data"
        BACKUP_BASE="$HOME/backups/archon"
        # Update exports
        export APPDATA_PATH="$APPDATA_BASE"
        export DATA_PATH="$DATA_BASE"
    fi
    
    log_success "Prerequisites check completed"
}

create_directory_structure() {
    log_info "Creating directory structure..."
    
    # Create appdata directories
    mkdir -p "$APPDATA_BASE"/{server,mcp,agents,frontend}
    mkdir -p "$APPDATA_BASE"/logs/{server,mcp,agents,frontend}
    
    # Create data directories
    mkdir -p "$DATA_BASE"/{documents,embeddings,cache}
    
    # Create backup directory
    mkdir -p "$BACKUP_BASE"
    
    # Set permissions using PUID/PGID from environment
    # Source the .env file to get PUID/PGID values
    if [ -f "$UNRAID_DIR/.env" ]; then
        source "$UNRAID_DIR/.env"
    fi
    
    PUID_VALUE=${PUID:-99}
    PGID_VALUE=${PGID:-100}
    
    if [ -f /etc/unraid-version ]; then
        chown -R "$PUID_VALUE:$PGID_VALUE" "$APPDATA_BASE" 2>/dev/null || true
        chown -R "$PUID_VALUE:$PGID_VALUE" "$DATA_BASE" 2>/dev/null || true
        chown -R "$PUID_VALUE:$PGID_VALUE" "$BACKUP_BASE" 2>/dev/null || true
    fi
    
    log_success "Directory structure created"
}

setup_environment() {
    log_info "Setting up environment configuration..."
    
    ENV_FILE="$UNRAID_DIR/.env"
    ENV_TEMPLATE="$UNRAID_DIR/.env.unraid"
    
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "$ENV_TEMPLATE" ]; then
            cp "$ENV_TEMPLATE" "$ENV_FILE" || { log_error "Failed to create .env file from template"; exit 1; }
            
            # Pre-populate .env with any environment variables passed from CA
            # This prevents double entry and respects CA configuration
            log_info "Checking for environment variables from Community Applications..."
            
            # Helper function to update env file
            update_env_var() {
                local var_name="$1"
                local var_value="$2"
                if [ -n "$var_value" ]; then
                    # Escape special characters for sed (including & and ])
                    local escaped_value=$(printf '%s' "$var_value" | sed -e 's/[\\&|]/\\&/g' -e 's/\]/\\]/g')
                    sed -i "s|^${var_name}=.*|${var_name}=$escaped_value|" "$ENV_FILE"
                    log_info "  • Set $var_name from environment"
                fi
            }
            
            # Check and update all potentially passed environment variables
            [ -n "$SUPABASE_URL" ] && [ "$SUPABASE_URL" != "https://your-project.supabase.co" ] && update_env_var "SUPABASE_URL" "$SUPABASE_URL"
            [ -n "$SUPABASE_SERVICE_KEY" ] && [ "$SUPABASE_SERVICE_KEY" != "your-service-key-here" ] && update_env_var "SUPABASE_SERVICE_KEY" "$SUPABASE_SERVICE_KEY"
            [ -n "$OPENAI_API_KEY" ] && update_env_var "OPENAI_API_KEY" "$OPENAI_API_KEY"
            [ -n "$PUID" ] && update_env_var "PUID" "$PUID"
            [ -n "$PGID" ] && update_env_var "PGID" "$PGID"
            [ -n "$TZ" ] && update_env_var "TZ" "$TZ"
            [ -n "$FRONTEND_PORT" ] && update_env_var "FRONTEND_PORT" "$FRONTEND_PORT"
            [ -n "$SERVER_PORT" ] && update_env_var "SERVER_PORT" "$SERVER_PORT"
            [ -n "$MCP_PORT" ] && update_env_var "MCP_PORT" "$MCP_PORT"
            [ -n "$AGENTS_PORT" ] && update_env_var "AGENTS_PORT" "$AGENTS_PORT"
            [ -n "$LOG_LEVEL" ] && update_env_var "LOG_LEVEL" "$LOG_LEVEL"
            [ -n "$ENABLE_PROJECTS" ] && update_env_var "ENABLE_PROJECTS" "$ENABLE_PROJECTS"
            [ -n "$LOGFIRE_TOKEN" ] && update_env_var "LOGFIRE_TOKEN" "$LOGFIRE_TOKEN"
            [ -n "$COMPOSE_PROJECT_NAME" ] && update_env_var "COMPOSE_PROJECT_NAME" "$COMPOSE_PROJECT_NAME"
            [ -n "$REGISTRY_PREFIX" ] && update_env_var "REGISTRY_PREFIX" "$REGISTRY_PREFIX"
            
            # Source the updated file to get current values
            source "$ENV_FILE"
            
            # Only prompt for required values if they're still not set
            if [ -z "$SUPABASE_URL" ] || [ "$SUPABASE_URL" = "https://your-project.supabase.co" ]; then
                echo ""
                read -rp "Enter SUPABASE_URL (e.g. https://xxxxx.supabase.co): " SUPABASE_URL_INPUT
                if [ -n "$SUPABASE_URL_INPUT" ]; then
                    # Escape special characters for sed
                    SUPABASE_URL_ESCAPED=$(printf '%s\n' "$SUPABASE_URL_INPUT" | sed 's:[[\.*^$()+?{|]:\\&:g')
                    sed -i "s|^SUPABASE_URL=.*|SUPABASE_URL=$SUPABASE_URL_ESCAPED|" "$ENV_FILE"
                    SUPABASE_URL="$SUPABASE_URL_INPUT"
                fi
            fi
            
            if [ -z "$SUPABASE_SERVICE_KEY" ] || [ "$SUPABASE_SERVICE_KEY" = "your-service-key-here" ]; then
                echo ""
                read -rp "Enter SUPABASE_SERVICE_KEY: " SUPABASE_SERVICE_KEY_INPUT
                if [ -n "$SUPABASE_SERVICE_KEY_INPUT" ]; then
                    # Escape special characters for sed
                    SUPABASE_SERVICE_KEY_ESCAPED=$(printf '%s\n' "$SUPABASE_SERVICE_KEY_INPUT" | sed 's:[[\.*^$()+?{|]:\\&:g')
                    sed -i "s|^SUPABASE_SERVICE_KEY=.*|SUPABASE_SERVICE_KEY=$SUPABASE_SERVICE_KEY_ESCAPED|" "$ENV_FILE"
                    SUPABASE_SERVICE_KEY="$SUPABASE_SERVICE_KEY_INPUT"
                fi
            fi
            
            log_success "Environment configuration created and updated"
        else
            log_error "Environment template not found at $ENV_TEMPLATE"
            exit 1
        fi
    else
        log_info "Using existing .env file"
    fi
    
    # Validate required environment variables
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
        
        if [ -z "$SUPABASE_URL" ] || [ "$SUPABASE_URL" = "https://your-project.supabase.co" ]; then
            log_error "SUPABASE_URL is not configured in .env file"
            exit 1
        fi
        
        if [ -z "$SUPABASE_SERVICE_KEY" ] || [ "$SUPABASE_SERVICE_KEY" = "your-service-key-here" ]; then
            log_error "SUPABASE_SERVICE_KEY is not configured in .env file"
            exit 1
        fi
        
        # Check Supabase connectivity
        if command -v curl >/dev/null; then
            log_info "Checking Supabase connectivity..."
            if ! curl -sI --connect-timeout 5 "$SUPABASE_URL" >/dev/null; then
                log_warning "Cannot reach SUPABASE_URL: $SUPABASE_URL. Check connectivity and URL format."
            else
                log_success "Supabase URL is reachable"
            fi
        fi
    fi
    
    log_success "Environment configuration validated"
}

check_port_conflicts() {
    log_info "Checking for port conflicts..."
    
    # Source environment to get port settings
    if [ -f "$UNRAID_DIR/.env" ]; then
        source "$UNRAID_DIR/.env"
    fi
    
    # Default ports
    FRONTEND_PORT=${FRONTEND_PORT:-3737}
    SERVER_PORT=${SERVER_PORT:-8181}
    MCP_PORT=${MCP_PORT:-8051}
    AGENTS_PORT=${AGENTS_PORT:-8052}
    
    REQUIRED_PORTS=("$FRONTEND_PORT" "$SERVER_PORT" "$MCP_PORT" "$AGENTS_PORT")
    CONFLICTING_PORTS=()
    
    # Check each required port
    for port in "${REQUIRED_PORTS[@]}"; do
        if command -v netstat &> /dev/null; then
            if netstat -tuln 2>/dev/null | grep -q ":$port "; then
                CONFLICTING_PORTS+=("$port")
            fi
        elif command -v ss &> /dev/null; then
            if ss -tuln 2>/dev/null | grep -q ":$port "; then
                CONFLICTING_PORTS+=("$port")
            fi
        elif [ -e "/proc/net/tcp" ]; then
            # Convert port to hex for /proc/net/tcp check
            port_hex=$(printf "%04X" "$port")
            if grep -q ":$port_hex " /proc/net/tcp 2>/dev/null; then
                CONFLICTING_PORTS+=("$port")
            fi
        else
            log_warning "No network tools available for port conflict checking"
            break
        fi
    done
    
    # Report conflicts
    if [ ${#CONFLICTING_PORTS[@]} -gt 0 ]; then
        log_warning "Port conflicts detected:"
        for port in "${CONFLICTING_PORTS[@]}"; do
            # Try to identify what's using the port
            if command -v netstat &> /dev/null; then
                process=$(netstat -tulnp 2>/dev/null | grep ":$port " | awk '{print $7}' | head -1)
            elif command -v ss &> /dev/null; then
                process=$(ss -tulnp 2>/dev/null | grep ":$port " | awk '{print $6}' | head -1)
            else
                process="unknown"
            fi
            log_warning "  • Port $port (used by: ${process:-unknown})"
        done
        
        echo ""
        log_info "To resolve port conflicts:"
        log_info "  1. Stop the conflicting services, or"
        log_info "  2. Update ports in $UNRAID_DIR/.env file:"
        log_info "     FRONTEND_PORT=3738  # Change from $FRONTEND_PORT"
        log_info "     SERVER_PORT=8182    # Change from $SERVER_PORT"
        log_info "     MCP_PORT=8053       # Change from $MCP_PORT"
        log_info "     AGENTS_PORT=8054    # Change from $AGENTS_PORT"
        echo ""
        
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Deployment cancelled due to port conflicts"
            exit 1
        fi
        
        log_warning "Proceeding with port conflicts - deployment may fail"
    else
        log_success "No port conflicts detected"
    fi
}

check_network_conflicts() {
    log_info "Checking for network conflicts..."
    
    # Source environment to get network settings
    if [ -f "$UNRAID_DIR/.env" ]; then
        source "$UNRAID_DIR/.env"
    fi
    
    NETWORK_SUBNET=${NETWORK_SUBNET:-"172.20.0.0/16"}
    BRIDGE_NAME=${BRIDGE_NAME:-"br-archon"}
    
    # Check if the bridge name already exists
    if docker network ls --format "{{.Name}}" | grep -q "^${BRIDGE_NAME}$"; then
        log_warning "Network bridge '$BRIDGE_NAME' already exists"
        
        # Check if it has the right subnet
        existing_subnet=$(docker network inspect "$BRIDGE_NAME" --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}' 2>/dev/null || echo "")
        if [ "$existing_subnet" != "$NETWORK_SUBNET" ]; then
            log_warning "Existing bridge has different subnet: $existing_subnet vs $NETWORK_SUBNET"
            log_info "Will use existing network configuration"
        fi
    fi
    
    # Check for subnet conflicts with existing networks using robust CIDR overlap detection
    if command -v python3 >/dev/null 2>&1; then
        # Use Python for proper CIDR overlap checking
        conflicting_networks=$(python3 - <<EOF
import ipaddress
import subprocess
import json
import sys

try:
    # Parse our target network
    target_network = ipaddress.ip_network("$NETWORK_SUBNET")
    
    # Get all docker networks and their subnets
    networks_result = subprocess.run(
        ['docker', 'network', 'ls', '--format', '{{.Name}}'],
        capture_output=True, text=True, check=True
    )
    
    conflicting = []
    for network_name in networks_result.stdout.strip().split('\n'):
        if not network_name or network_name == "$BRIDGE_NAME":
            continue
            
        try:
            inspect_result = subprocess.run(
                ['docker', 'network', 'inspect', network_name, '--format', '{{json .IPAM.Config}}'],
                capture_output=True, text=True, check=True
            )
            
            # Parse IPAM config
            ipam_config = json.loads(inspect_result.stdout.strip())
            if not ipam_config:
                continue
                
            for config in ipam_config:
                if 'Subnet' in config and config['Subnet']:
                    try:
                        existing_network = ipaddress.ip_network(config['Subnet'])
                        # Check for overlap
                        if target_network.overlaps(existing_network):
                            conflicting.append(f"{network_name}: {config['Subnet']}")
                    except ValueError:
                        # Invalid subnet format, skip
                        continue
                        
        except (subprocess.CalledProcessError, json.JSONDecodeError, ValueError):
            # Skip networks we can't inspect
            continue
    
    # Output conflicting networks
    for conflict in conflicting:
        print(conflict)
        
except Exception as e:
    # Fallback to simpler check if Python fails
    sys.exit(1)
EOF
)"
    else
        # Fallback to simpler subnet matching if Python not available
        log_warning "Python3 not available, using simplified network conflict detection"
        subnet_base=$(echo "$NETWORK_SUBNET" | cut -d'.' -f1-2)
        conflicting_networks=$(docker network ls --format "{{.Name}}" | xargs -I {} sh -c 'docker network inspect {} --format "{{.Name}}: {{range .IPAM.Config}}{{.Subnet}}{{end}}" 2>/dev/null' | grep "^.*: ${subnet_base}\..*" | grep -v "^${BRIDGE_NAME}:" || true)
    fi
    
    if [ -n "$conflicting_networks" ]; then
        log_warning "Found networks with conflicting subnet ranges:"
        echo "$conflicting_networks"
        log_info "Consider updating NETWORK_SUBNET in .env to avoid conflicts"
        log_info "Example: NETWORK_SUBNET=172.21.0.0/16"
        
        read -p "Continue with current network configuration? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_error "Deployment cancelled. Please update network settings in .env file."
            exit 1
        fi
    fi
    
    log_success "Network configuration validated"
}

validate_build_context() {
    log_info "Validating build context..."
    
    if [ "$BUILD_FROM_SOURCE" = "true" ]; then
        # Check if we have the source directories for building
        local missing_dirs=()
        
        if [ ! -d "$PROJECT_ROOT/python" ]; then
            missing_dirs+=("python/")
        fi
        if [ ! -d "$PROJECT_ROOT/archon-ui-main" ]; then
            missing_dirs+=("archon-ui-main/")
        fi
        
        if [ ${#missing_dirs[@]} -gt 0 ]; then
            log_error "BUILD_FROM_SOURCE=true but missing source directories: ${missing_dirs[*]}"
            log_error "Either clone the full repository or set BUILD_FROM_SOURCE=false"
            exit 1
        fi
        
        log_success "Build context validated"
    else
        log_info "Using pre-built images (BUILD_FROM_SOURCE=false)"
    fi
}

pull_docker_images() {
    log_info "Pulling Docker images..."
    
    # Source environment to get registry prefix
    if [ -f "$UNRAID_DIR/.env" ]; then
        source "$UNRAID_DIR/.env"
    fi
    REGISTRY_PREFIX=${REGISTRY_PREFIX:-"ghcr.io/coleam00"}
    
    # Try to pull pre-built images first
    docker pull "${REGISTRY_PREFIX}/archon-server:latest" 2>/dev/null || true
    docker pull "${REGISTRY_PREFIX}/archon-mcp:latest" 2>/dev/null || true
    docker pull "${REGISTRY_PREFIX}/archon-agents:latest" 2>/dev/null || true
    docker pull "${REGISTRY_PREFIX}/archon-frontend:latest" 2>/dev/null || true
    
    log_success "Docker images ready"
}

deploy_stack() {
    log_info "Deploying Archon stack..."
    
    cd "$UNRAID_DIR"
    
    # Use the Unraid-optimized compose file
    COMPOSE_FILE="docker-compose.unraid.yml"
    
    if [ ! -f "$COMPOSE_FILE" ]; then
        log_error "Docker Compose file not found: $COMPOSE_FILE"
        exit 1
    fi
    
    # Stop existing containers if running
    log_info "Stopping any existing Archon containers..."
    PROJECT_NAME="${COMPOSE_PROJECT_NAME:-archon}"
    
    # Source environment to get RUN_AS_ROOT setting
    if [ -f "$UNRAID_DIR/.env" ]; then
        source "$UNRAID_DIR/.env"
    fi
    
    # Determine compose args based on whether we're using base or unraid compose
    if [ -f ../docker-compose.yml ]; then
        # Using base compose file, include override
        STOP_COMPOSE_ARGS="-f ../docker-compose.yml -f docker-compose.override.yml"
    else
        # Using unraid compose file, no override needed
        STOP_COMPOSE_ARGS="-f $COMPOSE_FILE"
    fi
    
    # Add root mode override if enabled
    if [ "${RUN_AS_ROOT:-false}" = "true" ]; then
        STOP_COMPOSE_ARGS="$STOP_COMPOSE_ARGS -f docker-compose.unraid-root.yml"
    fi
    
    $DOCKER_COMPOSE_BIN -p "$PROJECT_NAME" $STOP_COMPOSE_ARGS down 2>/dev/null || true
    
    # Start the stack with conditional building
    log_info "Starting Archon services..."
    if [ -f ../docker-compose.yml ]; then
        # Using base docker-compose.yml, include override
        if [ "$BUILD_FROM_SOURCE" = "true" ] && [ -f docker-compose.unraid-build.yml ]; then
            COMPOSE_ARGS="-f ../docker-compose.yml -f docker-compose.override.yml -f docker-compose.unraid-build.yml"
            if [ "${RUN_AS_ROOT:-false}" = "true" ]; then
                COMPOSE_ARGS="$COMPOSE_ARGS -f docker-compose.unraid-root.yml"
            fi
            $DOCKER_COMPOSE_BIN -p "$PROJECT_NAME" $COMPOSE_ARGS up -d --build
        else
            COMPOSE_ARGS="-f ../docker-compose.yml -f docker-compose.override.yml"
            if [ "${RUN_AS_ROOT:-false}" = "true" ]; then
                COMPOSE_ARGS="$COMPOSE_ARGS -f docker-compose.unraid-root.yml"
            fi
            $DOCKER_COMPOSE_BIN -p "$PROJECT_NAME" $COMPOSE_ARGS up -d
        fi
    else
        # Using unraid compose file, no override needed
        if [ "$BUILD_FROM_SOURCE" = "true" ] && [ -f docker-compose.unraid-build.yml ]; then
            COMPOSE_ARGS="-f $COMPOSE_FILE -f docker-compose.unraid-build.yml"
            if [ "${RUN_AS_ROOT:-false}" = "true" ]; then
                COMPOSE_ARGS="$COMPOSE_ARGS -f docker-compose.unraid-root.yml"
            fi
            $DOCKER_COMPOSE_BIN -p "$PROJECT_NAME" $COMPOSE_ARGS up -d --build
        elif [ "$BUILD_FROM_SOURCE" = "true" ]; then
            log_warning "BUILD_FROM_SOURCE=true but docker-compose.unraid-build.yml not found, using standard compose"
            COMPOSE_ARGS="-f $COMPOSE_FILE"
            if [ "${RUN_AS_ROOT:-false}" = "true" ]; then
                COMPOSE_ARGS="$COMPOSE_ARGS -f docker-compose.unraid-root.yml"
            fi
            $DOCKER_COMPOSE_BIN -p "$PROJECT_NAME" $COMPOSE_ARGS up -d --build
        else
            COMPOSE_ARGS="-f $COMPOSE_FILE"
            if [ "${RUN_AS_ROOT:-false}" = "true" ]; then
                COMPOSE_ARGS="$COMPOSE_ARGS -f docker-compose.unraid-root.yml"
            fi
            $DOCKER_COMPOSE_BIN -p "$PROJECT_NAME" $COMPOSE_ARGS up -d
        fi
    fi
    
    if [ $? -eq 0 ]; then
        log_success "Archon stack deployed successfully"
    else
        log_error "Failed to deploy Archon stack"
        exit 1
    fi
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Source environment to get port settings
    if [ -f "$UNRAID_DIR/.env" ]; then
        source "$UNRAID_DIR/.env"
    fi
    
    # Wait for services to start
    log_info "Waiting for services to initialize..."
    sleep 10
    
    # Check service health - use environment variables for ports
    services=(
        "archon-server:${SERVER_PORT:-8181}" 
        "archon-mcp:${MCP_PORT:-8051}" 
        "archon-agents:${AGENTS_PORT:-8052}" 
        "archon-frontend:${FRONTEND_PORT:-3737}"
    )
    all_healthy=true
    
    for service in "${services[@]}"; do
        IFS=':' read -r name port <<< "$service"
        
        if docker ps | grep -q "$name"; then
            # Try to connect to the service if HTTP tools are available
            if [ "$HTTP_CHECK_AVAILABLE" = true ]; then
                if command -v curl &> /dev/null; then
                    if curl -f -s "http://localhost:$port/health" > /dev/null 2>&1 || \
                       curl -f -s "http://localhost:$port/" > /dev/null 2>&1; then
                        log_success "$name is running and accessible on port $port"
                    else
                        log_warning "$name is running but health check failed on port $port"
                        all_healthy=false
                    fi
                elif command -v wget &> /dev/null; then
                    if wget -q --spider "http://localhost:$port/health" 2>/dev/null || \
                       wget -q --spider "http://localhost:$port/" 2>/dev/null; then
                        log_success "$name is running and accessible on port $port"
                    else
                        log_warning "$name is running but health check failed on port $port"
                        all_healthy=false
                    fi
                fi
            else
                log_success "$name is running (HTTP check skipped - no curl/wget)"
            fi
        else
            log_error "$name is not running"
            all_healthy=false
        fi
    done
    
    if [ "$all_healthy" = true ]; then
        log_success "All services are healthy"
    else
        log_warning "Some services may need additional time to initialize"
    fi
}

show_post_deployment_info() {
    log_info "Deployment Summary"
    echo ""
    echo "======================================"
    echo "Archon has been deployed successfully!"
    echo "======================================"
    echo ""
    
    # Source environment to get port settings
    if [ -f "$UNRAID_DIR/.env" ]; then
        source "$UNRAID_DIR/.env"
    fi
    
    # Detect IP address with fallbacks
    SERVER_IP=""
    
    # Try hostname -I first
    if command -v hostname &> /dev/null; then
        SERVER_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
    fi
    
    # Fallback to ip command on br0
    if [ -z "$SERVER_IP" ] && command -v ip &> /dev/null; then
        SERVER_IP=$(ip -4 addr show br0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
    fi
    
    # Fallback to hostname -i
    if [ -z "$SERVER_IP" ] && command -v hostname &> /dev/null; then
        SERVER_IP=$(hostname -i 2>/dev/null | awk '{print $1}')
    fi
    
    # Final fallback to localhost
    if [ -z "$SERVER_IP" ]; then
        SERVER_IP="localhost"
        log_warning "Could not detect server IP address, using localhost"
    fi
    
    echo "Access Points:"
    echo "  Web UI:        http://${SERVER_IP}:${FRONTEND_PORT:-3737}"
    echo "  API Server:    http://${SERVER_IP}:${SERVER_PORT:-8181}"
    echo "  MCP Server:    http://${SERVER_IP}:${MCP_PORT:-8051}"
    echo "  Agents Server: http://${SERVER_IP}:${AGENTS_PORT:-8052}"
    echo ""
    echo "Data Locations:"
    echo "  AppData:       $APPDATA_BASE"
    echo "  Documents:     $DATA_BASE"
    echo "  Backups:       $BACKUP_BASE"
    echo ""
    echo "Next Steps:"
    echo "  1. Access the Web UI to complete initial setup"
    echo "  2. Configure your OpenAI API key in Settings"
    echo "  3. Start adding knowledge sources"
    echo "  4. Configure MCP integration with your AI coding assistant"
    echo ""
    echo "Management Commands:"
    if [ -f "$PROJECT_ROOT/docker-compose.yml" ]; then
        echo "  View logs:     $DOCKER_COMPOSE_BIN -f $PROJECT_ROOT/docker-compose.yml -f $UNRAID_DIR/docker-compose.override.yml logs -f"
        echo "  Stop services: $DOCKER_COMPOSE_BIN -f $PROJECT_ROOT/docker-compose.yml -f $UNRAID_DIR/docker-compose.override.yml down"
        echo "  Restart:       $DOCKER_COMPOSE_BIN -f $PROJECT_ROOT/docker-compose.yml -f $UNRAID_DIR/docker-compose.override.yml restart"
    else
        echo "  View logs:     $DOCKER_COMPOSE_BIN -f $UNRAID_DIR/docker-compose.unraid.yml logs -f"
        echo "  Stop services: $DOCKER_COMPOSE_BIN -f $UNRAID_DIR/docker-compose.unraid.yml down"
        echo "  Restart:       $DOCKER_COMPOSE_BIN -f $UNRAID_DIR/docker-compose.unraid.yml restart"
    fi
    echo ""
    
    # Send Unraid notification if available
    if command -v notify &> /dev/null; then
        notify -s "Archon Deployment" -d "Archon has been deployed successfully" -i "normal"
    fi
}

handle_error() {
    log_error "Deployment failed at line $1"
    log_info "Rolling back..."
    
    cd "$UNRAID_DIR" 2>/dev/null || true
    if [ -f ../docker-compose.yml ]; then
        $DOCKER_COMPOSE_BIN -f ../docker-compose.yml -f docker-compose.override.yml down 2>/dev/null || true
    else
        $DOCKER_COMPOSE_BIN -f docker-compose.unraid.yml down 2>/dev/null || true
    fi
    
    log_error "Deployment rolled back. Please check the logs for details."
    exit 1
}

# Trap errors
trap 'handle_error $LINENO' ERR

# Main execution
main() {
    echo ""
    echo "========================================="
    echo "    Archon Unraid Deployment Script"
    echo "========================================="
    echo ""
    
    check_prerequisites
    create_directory_structure
    setup_environment
    check_port_conflicts
    check_network_conflicts
    validate_build_context
    pull_docker_images
    deploy_stack
    verify_deployment
    show_post_deployment_info
}

# Run main function
main "$@"