# Archon for Unraid

Complete deployment package for running Archon V2 Alpha on Unraid Server with optimized configurations, automated management, and Community Applications integration.

## 📋 Table of Contents

- [Overview](#overview)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Configuration](#configuration)
- [Management](#management)
- [Troubleshooting](#troubleshooting)
- [Advanced Topics](#advanced-topics)

## Overview

Archon on Unraid provides a fully integrated knowledge management system with MCP (Model Context Protocol) support for AI-powered development workflows. This deployment package includes:

- **Community Applications Templates** - One-click installation through Unraid's app store
- **Optimized Docker Configuration** - Unraid-specific volume mappings and resource limits
- **Automated Management Scripts** - Backup, restore, maintenance, and health monitoring
- **Persistent Storage** - Proper appdata and document storage following Unraid conventions
- **Security & Permissions** - Correct user/group mappings for Unraid (nobody:users)

### Architecture

Archon consists of four microservices:

1. **Frontend (Port 3737)** - React-based web interface
2. **Main Server (Port 8181)** - FastAPI backend with Socket.IO
3. **MCP Server (Port 8051)** - Model Context Protocol server for AI integrations
4. **Agents Service (Port 8052)** - PydanticAI agents for AI/ML operations

## Prerequisites

### System Requirements

- **Unraid Server** 6.9.0 or later
- **Docker** with Docker Compose plugin
- **RAM** Minimum 4GB available
- **Storage** Minimum 10GB free space in appdata share
- **Network** Ports 3737, 8181, 8051, 8052 available

### Required Unraid Plugins

1. **Community Applications** (required for template installation)
   ```
   Install from: Apps > Plugins > Community Applications
   ```

2. **User Scripts** (optional, for automated backups)
   ```
   Install from: Apps > Plugins > User Scripts
   ```

3. **NerdTools** (optional, for advanced health checking)
   ```
   Install from: Apps > Plugins > NerdTools
   Enable: curl, wget, jq (for enhanced health monitoring)
   ```

### External Services

- **Supabase Account** - Required for database and vector storage
  - Sign up at [supabase.com](https://supabase.com)
  - Create a new project
  - Note your project URL and service key

- **OpenAI API Key** (optional)
  - Can be configured later through the UI
  - Required for AI features

## Installation

### Method 1: Community Applications (Recommended)

1. **Install via Community Apps**
   - Go to Unraid Web UI > Apps
   - Search for "Archon"
   - Click "Install" on the Archon Stack template
   - Configure required environment variables:
     - `SUPABASE_URL`: Your Supabase project URL
     - `SUPABASE_SERVICE_KEY`: Your Supabase service key
   - Click "Apply"

2. **Verify Installation**
   - Check Docker tab for running containers
   - Access Web UI at `http://[YOUR-UNRAID-IP]:3737`

### Method 2: Automated Script

1. **SSH into your Unraid server**
   ```bash
   ssh root@your-unraid-ip
   ```

2. **Clone the repository**
   ```bash
   cd /mnt/user/appdata
   git clone https://github.com/coleam00/Archon.git
   cd archon/unraid
   ```

3. **Run deployment script**
   ```bash
   chmod +x scripts/deploy.sh
   ./scripts/deploy.sh
   ```

4. **Configure environment**
   - Edit `/mnt/user/appdata/archon/unraid/.env`
   - Add your Supabase credentials
   - Run deployment script again

### Method 3: Manual Docker Compose

1. **Create directory structure**
   ```bash
   mkdir -p /mnt/user/appdata/archon/{server,mcp,agents,frontend,logs}
   mkdir -p /mnt/user/archon-data
   ```

2. **Copy configuration files**
   ```bash
   cp unraid/docker-compose.unraid.yml /mnt/user/appdata/archon/
   cp unraid/.env.unraid /mnt/user/appdata/archon/.env
   ```

3. **Edit environment file**
   ```bash
   nano /mnt/user/appdata/archon/.env
   # Add your Supabase credentials
   ```

4. **Deploy stack**
   ```bash
   cd /mnt/user/appdata/archon
   docker compose -f docker-compose.unraid.yml up -d
   ```

## Configuration

### Environment Variables

Key configuration options in `.env`:

```env
# Required
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-key-here

# Optional
OPENAI_API_KEY=sk-...  # Can be set via UI

# Unraid-specific
PUID=99                 # nobody user
PGID=100                # users group
TZ=America/New_York     # Your timezone

# Ports (change if conflicts)
FRONTEND_PORT=3737
SERVER_PORT=8181
MCP_PORT=8051
AGENTS_PORT=8052

# Resource Limits
SERVER_CPU_LIMIT=2
SERVER_MEMORY_LIMIT=2G
```

#### Resource Limits Compatibility

**Important**: CPU limits via `cpus:` in Docker Compose v3 may be ignored by some Unraid Docker versions. Memory limits using `mem_limit` are generally honored.

**Recommended CPU Limiting Approaches:**

**Option 1: Community Applications Templates (Recommended)**
- Set CPU limits per container in Unraid CA templates using `<ExtraParams>--cpus=2</ExtraParams>`
- Or configure CPU pinning/limits directly in Unraid UI after container creation
- This ensures CPU limits are applied at the container runtime level

**Option 2: Unraid UI Configuration**
- After deploying containers, go to Docker tab in Unraid UI
- Edit each container and set CPU limits in the container settings
- Use "CPU Pinning" to assign specific cores to containers

**Supported Resource Controls:**
- `mem_limit`: Memory limit (e.g., `2G`, `1024M`) - **Works reliably**
- `cpus`: CPU limit as number of cores (e.g., `2`, `1.5`) - **May be ignored**
- `mem_reservation`: Memory reservation (soft limit)
- `cpu_quota` and `cpu_period`: Advanced CPU control

**Not Supported in Unraid:**
- Docker Swarm `deploy:` blocks are ignored
- `deploy.resources.limits` - use `mem_limit` for memory, CA templates for CPU
- `deploy.resources.reservations` - use `mem_reservation` instead

**Current Configuration:**
The compose files use `mem_limit` for memory and remove `cpus:` settings to avoid confusion. CPU limits should be set via Unraid UI or CA template `ExtraParams`.

### Frontend Service Environment Variables

**IMPORTANT**: The frontend image `ghcr.io/archon/archon-frontend:latest` is built as a static site and does NOT read runtime environment variables by default. 

#### Runtime Configuration Options:

**Option 1: Use Pre-built Static Image (Default)**
- Environment variables are set at build time, not runtime
- URLs are auto-detected based on container network
- Suitable for standard deployments

**Option 2: Runtime Configuration Injection (Recommended for Custom URLs)**
- Build and use the included `Dockerfile.frontend` for runtime configuration
- Generates `/usr/share/nginx/html/config.js` from environment variables at startup
- Reads `VITE_API_URL`, `VITE_MCP_URL`, `VITE_AGENTS_URL` at runtime
- Example:
  ```bash
  # Build custom frontend image with runtime config
  cd unraid/
  docker build -f Dockerfile.frontend -t archon-frontend-runtime .
  
  # Use in docker-compose by overriding image:
  # image: archon-frontend-runtime
  ```

**Option 3: Custom Build from Source**
- Use `BUILD_FROM_SOURCE=true` in deployment
- Modify build-time variables in Dockerfile or build args

#### Current Environment Variables (Build-time only):
- `VITE_API_URL`: Backend API server URL
- `VITE_MCP_URL`: MCP server URL  
- `VITE_AGENTS_URL`: Agents service URL

#### Troubleshooting Frontend Connectivity:
If the frontend cannot connect to backend services:
1. Check container network connectivity
2. Verify service URLs in browser developer tools
3. Consider using Option 2 above for custom runtime configuration

### Port Configuration

Default port mappings:

| Service | Internal | External | Description |
|---------|----------|----------|-------------|
| Frontend | 80 | 3737 | Web UI |
| Server | 8181 | 8181 | API Server |
| MCP | 8051 | 8051 | MCP Protocol |
| Agents | 8052 | 8052 | AI Agents |

To change ports, edit both:
- `.env` file (external ports)
- `docker-compose.unraid.yml` (port mappings)

### Storage Locations

Archon uses standard Unraid paths:

| Type | Default Path | Purpose |
|------|--------------|---------|
| AppData | `/mnt/user/appdata/archon` | Configuration & state |
| Documents | `/mnt/user/archon-data` | Knowledge base storage |
| Backups | `/mnt/user/backups/archon` | Backup archives |
| Logs | `/mnt/user/appdata/archon/logs` | Service logs |

### User Permissions

Archon runs as nobody:users (99:100) by default. To change:

1. Edit `.env`:
   ```env
   PUID=1000  # Your user ID
   PGID=1000  # Your group ID
   ```

2. Fix existing permissions:
   ```bash
   chown -R 1000:1000 /mnt/user/appdata/archon
   chown -R 1000:1000 /mnt/user/archon-data
   ```

#### Non-Root Runtime Compatibility

**Troubleshooting Container Startup Issues:**

If containers fail to start with user mapping errors, the images may require root access. In this case:

**Option 1: Disable User Mapping (Recommended)**
1. Set `RUN_AS_ROOT=true` in your `.env` file
2. Remove or comment out `user:` mappings in docker-compose files
3. Restart the stack

**Option 2: Use Root User Explicitly**
1. Edit docker-compose files to set `user: "0:0"` (root:root)
2. **Security Note**: This reduces security by running as root

**Example troubleshooting:**
```bash
# If you see errors like "operation not permitted" or "permission denied"
# during container startup, try running as root:

# Edit .env file
echo "RUN_AS_ROOT=true" >> /mnt/user/appdata/archon/.env

# Or manually set user to root in compose files
# user: "0:0"  # root:root instead of "${PUID:-99}:${PGID:-100}"
```

**Detection**: Container logs showing permission errors during startup typically indicate non-root incompatibility.

## Building from Source

To build Archon from source instead of using pre-built images:

1. Clone the full repository with all source code
2. Set `BUILD_FROM_SOURCE=true` in your `.env` file
3. Run the deployment script

The `docker-compose.unraid-build.yml` file contains the build configuration.

**Note:** Building requires the complete source tree including:
- `python/` directory (backend services)
- `archon-ui-main/` directory (frontend)

## Important Notes

### Temporary File System (tmpfs) Considerations

Unraid often uses tmpfs (RAM-based) for `/tmp`. This can cause issues with:
- Large backup/restore operations that use temporary files
- Scripts that extract large archives

The Archon scripts have been modified to use disk-backed paths instead of `/tmp` to avoid exhausting RAM. Temporary files are stored in:
- Backup operations: `$BACKUP_PATH/.tmp/`
- Restore operations: `$BACKUP_PATH/.tmp/`

These are automatically cleaned up after operations complete.

## Management

### Starting and Stopping Services

**Using Unraid Docker UI:**
- Go to Docker tab
- Click on container name
- Select Start/Stop/Restart

**Using Command Line:**
```bash
cd /mnt/user/appdata/archon/unraid

# Stop all services
docker compose -f docker-compose.unraid.yml down

# Start all services
docker compose -f docker-compose.unraid.yml up -d

# Restart specific service
docker compose -f docker-compose.unraid.yml restart archon-server

# View logs
docker compose -f docker-compose.unraid.yml logs -f
```

### Backup and Restore

#### Automated Backups with User Scripts

1. **Install User Scripts plugin**
2. **Create new script** "Archon Backup"
3. **Add script content:**
   ```bash
   #!/bin/bash
   /mnt/user/appdata/archon/unraid/scripts/backup.sh full
   ```
4. **Set schedule** (e.g., daily at 2 AM)

#### Manual Backup

```bash
# Full backup
/mnt/user/appdata/archon/unraid/scripts/backup.sh full

# Incremental backup
/mnt/user/appdata/archon/unraid/scripts/backup.sh incremental
```

#### Restore from Backup

```bash
# Restore latest backup
/mnt/user/appdata/archon/unraid/scripts/restore.sh

# Restore specific backup
/mnt/user/appdata/archon/unraid/scripts/restore.sh archon_backup_20240101_120000.tar.gz
```

### Health Monitoring

#### Quick Health Check
```bash
/mnt/user/appdata/archon/unraid/scripts/health-check.sh quick
```

#### Comprehensive Health Check
```bash
/mnt/user/appdata/archon/unraid/scripts/health-check.sh comprehensive
```

#### Continuous Monitoring
```bash
/mnt/user/appdata/archon/unraid/scripts/health-check.sh monitor
```

### Maintenance Tasks

#### Run Full Maintenance
```bash
/mnt/user/appdata/archon/unraid/scripts/maintenance.sh full
```

#### Cleanup Logs and Docker
```bash
/mnt/user/appdata/archon/unraid/scripts/maintenance.sh cleanup
```

#### Check for Updates
```bash
/mnt/user/appdata/archon/unraid/scripts/maintenance.sh update
```

### Monitoring and Logs

#### View Container Logs
```bash
# All services
docker compose -f docker-compose.unraid.yml logs -f

# Specific service
docker logs -f archon-server

# Last 100 lines
docker logs --tail 100 archon-mcp
```

#### Check Resource Usage
```bash
# Docker stats
docker stats $(docker ps --format '{{.Names}}' | grep archon)

# Disk usage
du -sh /mnt/user/appdata/archon
du -sh /mnt/user/archon-data
```

## Troubleshooting

### Common Issues

#### Services Won't Start

1. **Check ports are available:**
   ```bash
   netstat -tuln | grep -E "3737|8181|8051|8052"
   ```

2. **Verify environment configuration:**
   ```bash
   cat /mnt/user/appdata/archon/unraid/.env
   # Ensure SUPABASE_URL and SUPABASE_SERVICE_KEY are set
   ```

3. **Check Docker logs:**
   ```bash
   docker logs archon-server
   ```

#### Service Startup Dependencies

**Note on Service Dependencies:**

Services now use built-in health checks and wait scripts instead of Docker Compose `depends_on` conditions for better Unraid compatibility:

- **MCP and Agents services** wait for the main server to be healthy before starting
- **Frontend service** waits for all backend services to be available
- **Health checks** use `curl` or `wget` fallbacks for better compatibility with minimal images
- **Restart policies** ensure services retry connections if dependencies restart

If services appear to start but don't respond:
1. Check that the `wait-for-http.sh` script is executable in the container
2. Verify the health check endpoints are responding:
   ```bash
   curl http://localhost:8181/health
   curl http://localhost:8051/health
   curl http://localhost:8052/health
   ```
3. Services will automatically retry if dependencies are temporarily unavailable

#### Database Connection Errors

1. **Verify Supabase credentials:**
   - Check URL format: `https://[project-id].supabase.co`
   - Ensure service key (not anon key) is used

2. **Test connectivity:**
   ```bash
   curl -I https://your-project.supabase.co
   ```

#### Permission Denied Errors

1. **Fix ownership:**
   ```bash
   chown -R 99:100 /mnt/user/appdata/archon
   chown -R 99:100 /mnt/user/archon-data
   ```

2. **Check Docker user mapping:**
   ```bash
   docker exec archon-server id
   # Should show uid=99(nobody) gid=100(users)
   ```

#### High Resource Usage

1. **Check container limits:**
   ```bash
   docker stats --no-stream
   ```

2. **Adjust limits in `.env`:**
   ```env
   SERVER_CPU_LIMIT=4
   SERVER_MEMORY_LIMIT=4G
   ```

3. **Restart services:**
   ```bash
   docker compose -f docker-compose.unraid.yml restart
   ```

### Recovery Procedures

#### Service Recovery
```bash
# Automatic recovery
/mnt/user/appdata/archon/unraid/scripts/health-check.sh comprehensive

# Manual service restart
docker restart archon-server
```

#### Data Recovery
```bash
# From backup
/mnt/user/appdata/archon/unraid/scripts/restore.sh

# From safety backup (if restore fails)
# Get the exact path from the restore script's safety backup location
SAFETY_BACKUP_PATH=$(cat /mnt/user/backups/archon/.tmp/safety_backup_path 2>/dev/null)
if [ -n "$SAFETY_BACKUP_PATH" ] && [ -d "$SAFETY_BACKUP_PATH" ]; then
  cp -r "$SAFETY_BACKUP_PATH/appdata_current"/* /mnt/user/appdata/archon/
else
  echo "Safety backup not found. Check /mnt/user/backups/archon/.tmp/ for available backups."
fi
```

## Advanced Topics

### Security Considerations

#### Version Pinning for Remote Script Execution

**SECURITY NOTE**: The Archon Stack template executes a remote deployment script with Docker socket access. For production deployments:

1. **Use Pinned Releases** (Recommended):
   - Set `ARCHON_RELEASE_VERSION` to a specific version like `v1.0.0`
   - This ensures reproducible deployments and prevents supply chain attacks
   - Example: `ARCHON_RELEASE_VERSION=v1.0.0`

2. **Risk Awareness**:
   - Remote script execution provides convenience but introduces security risks
   - The script has access to Docker daemon via mounted socket
   - Always review release notes before deploying new versions

3. **Alternative Secure Deployment**:
   - Download and review the deployment script manually
   - Use manual Docker Compose deployment for maximum control
   - Implement your own CI/CD pipeline for automated deployments

#### Container Security

- **User Mapping**: Run as nobody:users (99:100) by default
- **Network Isolation**: Services run in isolated Docker network
- **Secrets Management**: Environment variables are masked in templates
- **Resource Limits**: Memory and CPU limits prevent resource exhaustion

### GPU Acceleration

Enable GPU support for AI workloads:

1. **Install NVIDIA Driver plugin** (if using NVIDIA GPU)

2. **Edit `.env`:**
   ```env
   CUDA_VISIBLE_DEVICES=0
   NVIDIA_VISIBLE_DEVICES=all
   NVIDIA_DRIVER_CAPABILITIES=compute,utility
   ```

3. **Uncomment GPU section in `docker-compose.unraid.yml`:**
   ```yaml
   deploy:
     resources:
       reservations:
         devices:
           - driver: nvidia
             count: 1
             capabilities: [gpu]
   ```

### Custom Network Configuration

#### Automatic Network Conflict Detection

The deployment script automatically checks for network conflicts and guides you through resolution:

**Environment Variables for Network Configuration:**
```bash
# Custom network subnet (if needed to avoid conflicts)
NETWORK_SUBNET=172.20.0.0/16
# Custom bridge name (if needed to avoid conflicts)
BRIDGE_NAME=br-archon
```

**Common Network Conflicts:**
- VPN containers using similar subnet ranges
- Other Docker Compose stacks with overlapping networks
- Unraid VM networks in the same range

**Automatic Conflict Resolution:**
1. The script detects existing Docker networks
2. Checks for subnet range conflicts (e.g., 172.20.x.x)
3. Warns about potential issues
4. Suggests alternative subnet ranges
5. Prompts for confirmation before proceeding

**Manual Network Creation:**
If you need to create the network manually:

```bash
# Create custom bridge (change subnet if conflicts exist)
docker network create \
  --driver bridge \
  --subnet=172.21.0.0/16 \
  --opt com.docker.network.bridge.name=br-archon \
  archon-network
```

**Alternative Subnet Ranges:**
- `172.21.0.0/16` - Alternative private range
- `172.22.0.0/16` - Another alternative
- `10.10.0.0/16` - Class A private range
- `192.168.100.0/24` - Smaller subnet

### Integration with Other Unraid Apps

#### Nginx Proxy Manager

Add Archon to NPM:

1. **Create Proxy Host:**
   - Domain: `archon.yourdomain.com`
   - Forward IP: `[UNRAID-IP]`
   - Forward Port: `3737`
   - Enable Websockets Support

2. **SSL Configuration:**
   - Request Let's Encrypt certificate
   - Force SSL

#### Cloudflare Tunnel

Expose Archon securely:

1. **Install Cloudflare Tunnel docker**
2. **Configure tunnel routes:**
   - `archon.yourdomain.com` → `http://archon-frontend:80`
   - `api.archon.yourdomain.com` → `http://archon-server:8181`

### Performance Tuning

#### Database Optimization

1. **Increase connection pool:**
   ```env
   MAX_WORKERS=8
   DB_POOL_SIZE=20
   ```

2. **Enable query caching:**
   ```env
   ENABLE_CACHE=true
   CACHE_TTL=3600
   ```

#### Memory Optimization

1. **Adjust Node.js memory:**
   ```env
   NODE_OPTIONS=--max-old-space-size=4096
   ```

2. **Configure Python memory:**
   ```env
   PYTHONMALLOC=malloc
   ```

### Development Setup

For development on Unraid:

1. **Mount source code:**
   ```yaml
   volumes:
     - /mnt/user/dev/archon:/app:ro
   ```

2. **Enable hot reload:**
   ```env
   DEV_MODE=true
   VITE_HMR_HOST=your-unraid-ip
   ```

3. **Access development tools:**
   - Frontend: `http://[IP]:3737`
   - API Docs: `http://[IP]:8181/docs`

## Support

### Getting Help

- **GitHub Issues:** [github.com/coleam00/Archon/issues](https://github.com/coleam00/Archon/issues)
- **Documentation:** [docs.archon.dev](https://docs.archon.dev)
- **Community Forum:** [forum.archon.dev](https://forum.archon.dev)
- **Unraid Forum Thread:** [forums.unraid.net/archon](https://forums.unraid.net)

### Reporting Issues

When reporting issues, include:

1. **System Information:**
   ```bash
   cat /etc/unraid-version
   docker version
   ```

2. **Service Logs:**
   ```bash
   docker compose -f docker-compose.unraid.yml logs > archon-logs.txt
   ```

3. **Health Report:**
   ```bash
   /mnt/user/appdata/archon/unraid/scripts/health-check.sh report
   ```

### Contributing

Contributions are welcome! See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines.

## License

Archon is released under the MIT License. See [LICENSE](../LICENSE) for details.