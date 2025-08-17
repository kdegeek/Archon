# Archon Quick Install Guide for Unraid

Get Archon up and running on your Unraid server in minutes!

## 🚀 Quick Start (5 minutes)

### Option 1: Community Applications (Easiest)

1. **Open Unraid Web UI** → **Apps Tab**
2. **Search** for "Archon"
3. **Click Install** on "Archon Stack"
4. **Enter Required Settings:**
   - SUPABASE_URL: `https://your-project.supabase.co`
   - SUPABASE_SERVICE_KEY: `your-service-key`
5. **Click Apply**
6. **Access Archon** at `http://[YOUR-UNRAID-IP]:3737`

✅ **Done!** Archon is now running.

### Option 2: One-Line Install

SSH into your Unraid server and run:

**Recommended (Pinned Release):**
```bash
ARCHON_RELEASE_VERSION=v1.0.0 curl -sSL https://raw.githubusercontent.com/coleam00/Archon/main/unraid/scripts/deploy.sh | bash
```

**Development (Latest):**
```bash
curl -sSL https://raw.githubusercontent.com/coleam00/Archon/main/unraid/scripts/deploy.sh | bash
```

**What this does:**
- Downloads the specified Archon release (or latest from main)
- Automatically sets up directory structure in `/mnt/user/appdata/archon`
- Guides you through configuration
- Deploys all services with security best practices

**Security Note:** Using a pinned release version (e.g., v1.0.0) is recommended for production deployments to ensure supply chain security and stable operation.

## 📋 Prerequisites Checklist

Before installing, ensure you have:

- [ ] **Unraid 6.9+** installed
- [ ] **4GB RAM** available
- [ ] **10GB disk space** free
- [ ] **Supabase account** created
- [ ] **Supabase project** set up
- [ ] **Service key** copied (not anon key!)

### Getting Supabase Credentials

1. Go to [supabase.com](https://supabase.com)
2. Create account/project
3. Go to Settings → API
4. Copy:
   - **Project URL** (format: `https://xxxxx.supabase.co`)
   - **Service Role Key** (starts with `eyJ...`)

## 🛠️ Manual Installation

If automated methods don't work:

### Step 1: Create Directories

```bash
mkdir -p /mnt/user/appdata/archon
cd /mnt/user/appdata/archon
```

### Step 2: Download Files

```bash
# Download deployment package
wget https://github.com/coleam00/Archon/archive/main.zip
unzip main.zip
cd archon-main/unraid
```

### Step 3: Configure Environment

```bash
# Copy template
cp .env.unraid .env

# Edit with your credentials
nano .env
```

Add your Supabase credentials:
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-key-here
```

### Step 4: Deploy

```bash
# Make scripts executable
chmod +x scripts/*.sh

# Run deployment
./scripts/deploy.sh
```

## ✅ Post-Installation Setup

### 1. Verify Services

Check all services are running:

```bash
docker ps | grep archon
```

You should see 4 containers:
- archon-server
- archon-mcp
- archon-agents
- archon-frontend

### 2. Access Web UI

Open your browser and navigate to:
```
http://[YOUR-UNRAID-IP]:3737
```

### 3. Complete Initial Setup

1. **Set OpenAI API Key** (optional)
   - Go to Settings
   - Enter your OpenAI API key
   - Click Save

2. **Add Knowledge Sources**
   - Click "Add Source"
   - Enter website URL or upload documents
   - Wait for processing

3. **Configure MCP Integration**
   - For Cursor: Add to `.cursorrules`
   - For Windsurf: Configure MCP settings
   - Connection URL: `http://[YOUR-UNRAID-IP]:8051`

### 4. Set Up Automated Backups

Install User Scripts plugin and add:

```bash
#!/bin/bash
/mnt/user/appdata/archon/unraid/scripts/backup.sh incremental
```

Schedule: Daily at 2 AM

## 🔍 Quick Verification

Run health check:

```bash
/mnt/user/appdata/archon/unraid/scripts/health-check.sh quick
```

Expected output:
```
✓ archon-server
✓ archon-mcp
✓ archon-agents
✓ archon-frontend
```

## 🚨 Troubleshooting Quick Fixes

### Services Won't Start

```bash
# Check logs
docker logs archon-server

# Common fix: Verify Supabase credentials
cat /mnt/user/appdata/archon/unraid/.env
```

### Port Conflicts

Change ports in `.env`:
```env
FRONTEND_PORT=3738  # Changed from 3737
SERVER_PORT=8182    # Changed from 8181
```

Then restart:
```bash
docker compose -f docker-compose.unraid.yml restart
```

### Permission Issues

```bash
# Fix ownership
chown -R 99:100 /mnt/user/appdata/archon
```

## 📱 Mobile Access

### Local Network
Access from any device on your network:
```
http://[UNRAID-IP]:3737
```

### Remote Access (Secure)

Using **Cloudflare Tunnel** (recommended):

1. Install Cloudflare Tunnel from Community Apps
2. Configure tunnel to point to `archon-frontend:80`
3. Access via `https://archon.yourdomain.com`

Using **WireGuard VPN**:

1. Install WireGuard from Community Apps
2. Configure VPN access
3. Connect and use local IP

## 🔄 Updating Archon

### Automatic Updates

Enable in `.env`:
```env
AUTO_UPDATE=true
```

Run maintenance:
```bash
/mnt/user/appdata/archon/unraid/scripts/maintenance.sh update
```

### Manual Update

```bash
cd /mnt/user/appdata/archon/unraid
docker compose pull
docker compose up -d
```

## 💡 Next Steps

1. **Explore Features**
   - Upload documents for knowledge base
   - Create projects and tasks
   - Test MCP integration with your IDE

2. **Optimize Performance**
   - Adjust resource limits in `.env`
   - Enable GPU support if available
   - Configure caching

3. **Secure Your Installation**
   - Set up SSL with reverse proxy
   - Configure firewall rules
   - Enable authentication

## 🆘 Getting Help

- **Quick Help:** Run `/mnt/user/appdata/archon/unraid/scripts/health-check.sh`
- **Logs:** `docker logs archon-server`
- **Support:** [GitHub Issues](https://github.com/coleam00/Archon/issues)
- **Community:** [Unraid Forums](https://forums.unraid.net)

## 📊 System Requirements Reference

| Component | Minimum | Recommended |
|-----------|---------|-------------|
| CPU | 2 cores | 4+ cores |
| RAM | 4 GB | 8+ GB |
| Storage | 10 GB | 50+ GB |
| Network | 100 Mbps | 1 Gbps |
| Unraid | 6.9.0 | 6.12.0+ |

---

**Installation Complete!** 🎉

Your Archon instance is now running at `http://[YOUR-UNRAID-IP]:3737`

For detailed configuration and advanced features, see the [full documentation](README.md).