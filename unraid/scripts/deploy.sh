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
        
        # Clone the repository
        if command -v git &> /dev/null; then
            git clone https://github.com/archon/archon.git .
        else
            log_error "Git is not installed. Cannot clone repository."
            exit 1
        fi
        
        # Update paths to point to cloned repository
        PROJECT_ROOT="$INSTALL_DIR"
        UNRAID_DIR="$INSTALL_DIR/unraid"
        
        log_success "Repository cloned to $INSTALL_DIR"
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
    if ! docker compose version &> /dev/null; then
        log_error "Docker Compose plugin is not installed"
        exit 1
    fi
    
    # Check for curl or wget for HTTP verification
    if ! command -v curl &> /dev/null && ! command -v wget &> /dev/null; then
        log_warning "Neither curl nor wget is available. HTTP verification will be skipped."
        HTTP_CHECK_AVAILABLE=false
    else
        HTTP_CHECK_AVAILABLE=true
    fi
    
    # Check for required directories
    if [ ! -d "/mnt/user" ]; then
        log_warning "/mnt/user not found. Using local directories instead."
        APPDATA_BASE="$HOME/appdata/archon"
        DATA_BASE="$HOME/archon-data"
        BACKUP_BASE="$HOME/backups/archon"
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
    
    # Set permissions (Unraid default: nobody:users)
    if [ -f /etc/unraid-version ]; then
        chown -R 99:100 "$APPDATA_BASE" 2>/dev/null || true
        chown -R 99:100 "$DATA_BASE" 2>/dev/null || true
        chown -R 99:100 "$BACKUP_BASE" 2>/dev/null || true
    fi
    
    log_success "Directory structure created"
}

setup_environment() {
    log_info "Setting up environment configuration..."
    
    ENV_FILE="$UNRAID_DIR/.env"
    ENV_TEMPLATE="$UNRAID_DIR/.env.unraid"
    
    if [ ! -f "$ENV_FILE" ]; then
        if [ -f "$ENV_TEMPLATE" ]; then
            cp "$ENV_TEMPLATE" "$ENV_FILE"
            log_warning "Created .env file from template. Please edit it with your configuration."
            log_warning "Required: SUPABASE_URL and SUPABASE_SERVICE_KEY"
            echo ""
            read -p "Press Enter after configuring .env file to continue..."
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
        
        if [ -z "$SUPABASE_URL" ] || [ "$SUPABASE_URL" == "https://your-project.supabase.co" ]; then
            log_error "SUPABASE_URL is not configured in .env file"
            exit 1
        fi
        
        if [ -z "$SUPABASE_SERVICE_KEY" ] || [ "$SUPABASE_SERVICE_KEY" == "your-service-key-here" ]; then
            log_error "SUPABASE_SERVICE_KEY is not configured in .env file"
            exit 1
        fi
    fi
    
    log_success "Environment configuration validated"
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
    
    # Try to pull pre-built images first
    docker pull ghcr.io/archon/archon-server:latest 2>/dev/null || true
    docker pull ghcr.io/archon/archon-mcp:latest 2>/dev/null || true
    docker pull ghcr.io/archon/archon-agents:latest 2>/dev/null || true
    docker pull ghcr.io/archon/archon-frontend:latest 2>/dev/null || true
    
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
    docker compose -f "$COMPOSE_FILE" -f docker-compose.override.yml down 2>/dev/null || true
    
    # Start the stack with conditional building
    log_info "Starting Archon services..."
    if [ "$BUILD_FROM_SOURCE" = "true" ]; then
        docker compose -f "$COMPOSE_FILE" -f docker-compose.unraid-build.yml -f docker-compose.override.yml up -d --build
    else
        docker compose -f "$COMPOSE_FILE" -f docker-compose.override.yml up -d
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
    
    # Wait for services to start
    log_info "Waiting for services to initialize..."
    sleep 10
    
    # Check service health
    services=("archon-server:8181" "archon-mcp:8051" "archon-agents:8052" "archon-frontend:3737")
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
    echo "  Web UI:        http://${SERVER_IP}:3737"
    echo "  API Server:    http://${SERVER_IP}:8181"
    echo "  MCP Server:    http://${SERVER_IP}:8051"
    echo "  Agents Server: http://${SERVER_IP}:8052"
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
    echo "  View logs:     docker compose -f $UNRAID_DIR/docker-compose.unraid.yml -f $UNRAID_DIR/docker-compose.override.yml logs -f"
    echo "  Stop services: docker compose -f $UNRAID_DIR/docker-compose.unraid.yml -f $UNRAID_DIR/docker-compose.override.yml down"
    echo "  Restart:       docker compose -f $UNRAID_DIR/docker-compose.unraid.yml -f $UNRAID_DIR/docker-compose.override.yml restart"
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
    docker compose -f docker-compose.unraid.yml -f docker-compose.override.yml down 2>/dev/null || true
    
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
    validate_build_context
    pull_docker_images
    deploy_stack
    verify_deployment
    show_post_deployment_info
}

# Run main function
main "$@"