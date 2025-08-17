# Archon Community Applications Templates

This directory contains XML templates for deploying Archon on Unraid through Community Applications.

## Available Templates

### 1. archon-server.xml

**Core API Server** - The main backend service that handles API requests and database operations.

Includes:
- API Server (port 8181)
- Database integration
- WebSocket support

### 2. archon-frontend.xml

**Web User Interface** - The React-based frontend for interacting with Archon.

Includes:
- Web UI (port 3737)
- Real-time updates
- Project management interface

### 3. archon-mcp.xml

**Model Context Protocol Server** - Provides AI tools integration for development assistants.

Includes:
- MCP Server (port 8051)
- AI tool endpoints
- Knowledge base access

### 4. archon-agents.xml

**AI Agents Service** - PydanticAI-powered intelligent agents for advanced operations.

Includes:
- Agents Service (port 8052)
- Document processing
- Code analysis

**Use individual templates if:**
- You want to deploy services separately
- You have custom networking requirements
- You want granular control over each service
- You need to scale services independently

## Installation Instructions

### Method 1: Through Community Applications (Automatic)

The templates should appear automatically in Community Applications after the Archon repository is added to the app store.

1. Open Unraid Web UI
2. Go to Apps tab
3. Search for "Archon"
4. Select desired template
5. Configure and install

### Method 2: Manual Template Import

If templates don't appear automatically:

1. **Download the template file:**
   ```bash
   wget https://raw.githubusercontent.com/coleam00/Archon/main/unraid/templates/archon-server.xml
   ```

2. **Add to Community Applications:**
   - Go to Apps → Templates
   - Click "Add Template"
   - Paste the XML content
   - Save template

3. **Install from "User Templates":**
   - Go to Apps
   - Click "User Templates"
   - Select your imported template
   - Configure and install

## Template Configuration

### Required Settings

Both templates require:

| Setting | Description | Example |
|---------|-------------|---------|
| SUPABASE_URL | Your Supabase project URL | `https://xxxxx.supabase.co` |
| SUPABASE_SERVICE_KEY | Service role key (not anon!) | `eyJ...` (very long string) |

### Optional Settings

| Setting | Default | Description |
|---------|---------|-------------|
| OPENAI_API_KEY | (empty) | For AI features |
| PUID | 99 | User ID (nobody) |
| PGID | 100 | Group ID (users) |
| TZ | America/New_York | Timezone |
| LOG_LEVEL | INFO | Logging verbosity |

### Port Configuration

Default ports (change if conflicts exist):

| Service | Port | Used By |
|---------|------|---------|
| Frontend | 3737 | Web browser access |
| API Server | 8181 | Backend API |
| MCP Server | 8051 | AI tool integration |
| Agents | 8052 | AI agents |

### Storage Paths

Templates use standard Unraid paths:

| Path | Default | Purpose |
|------|---------|---------|
| AppData | `/mnt/user/appdata/archon` | Configuration |
| Data | `/mnt/user/archon-data` | Documents |
| Logs | `/mnt/user/appdata/archon/logs` | Log files |

## Template Customization

### Modifying Templates

To customize a template:

1. **Export existing template:**
   ```bash
   docker inspect archon-stack > custom-template.json
   ```

2. **Edit template values:**
   ```xml
   <Config Name="YourSetting" Target="ENV_VAR" Default="value">
   ```

3. **Common customizations:**

   **Change default port:**
   ```xml
   <Config Name="Frontend Port" Target="3737" Default="8080">8080</Config>
   ```

   **Add environment variable:**
   ```xml
   <Config Name="NEW_VAR" Target="NEW_VAR" Default="value" Type="Variable">value</Config>
   ```

   **Modify resource limits:**
   ```xml
   <ExtraParams>--memory=4g --cpus=2</ExtraParams>
   ```

### Creating Custom Templates

Base template structure:

```xml
<?xml version="1.0"?>
<Container version="2">
  <Name>YourContainer</Name>
  <Repository>image:tag</Repository>
  <Network>bridge</Network>
  <Config Name="Setting" Target="TARGET" Default="value" Type="Port|Path|Variable">value</Config>
  <!-- More configs -->
</Container>
```

## Advanced Configuration

### Multi-Instance Deployment

To run multiple Archon instances:

1. **Duplicate template** with new name
2. **Change container name** in XML
3. **Modify all ports** to avoid conflicts
4. **Use different appdata paths**
5. **Deploy separately**

### Custom Networking

For isolated network:

```xml
<Network>custom-bridge</Network>
<ExtraParams>--network archon-net</ExtraParams>
```

### GPU Support

Add GPU access:

```xml
<ExtraParams>--gpus all</ExtraParams>
<Config Name="CUDA_VISIBLE_DEVICES" Target="CUDA_VISIBLE_DEVICES" Default="0">0</Config>
```

### Resource Limits

Set CPU/Memory limits:

```xml
<ExtraParams>--memory=2g --memory-swap=2g --cpus=1.5</ExtraParams>
```

## Troubleshooting Templates

### Template Not Showing in Apps

1. **Check Community Applications is installed**
2. **Refresh app list:** Apps → Force Update
3. **Check template URL is accessible**
4. **Manually import template**

### Container Won't Start

1. **Check required variables are set**
2. **Verify ports are available:**
   ```bash
   netstat -tuln | grep 3737
   ```
3. **Check Docker logs:**
   ```bash
   docker logs archon-stack
   ```

### Permission Issues

Fix with proper User/Group IDs:

```xml
<Config Name="PUID" Target="PUID" Default="99">99</Config>
<Config Name="PGID" Target="PGID" Default="100">100</Config>
```

### Network Issues

Ensure bridge network exists:

```bash
docker network create bridge
```

## Integration with Other Templates

### Nginx Proxy Manager

Add reverse proxy support:

1. Install Nginx Proxy Manager
2. Create proxy host:
   - Domain: `archon.local`
   - Forward IP: `[UNRAID-IP]`
   - Forward Port: `3737`
   - Enable WebSocket support

### PostgreSQL Database

Use external database:

1. Install PostgreSQL template
2. Modify Archon template:
   ```xml
   <Config Name="DATABASE_URL" Target="DATABASE_URL">postgresql://...</Config>
   ```

### Cloudflare Tunnel

Secure external access:

1. Install Cloudflare Tunnel
2. Configure service:
   - Service: `http://archon-frontend:80`
   - Domain: `archon.yourdomain.com`

## Best Practices

### Security

- Always use SUPABASE_SERVICE_KEY (not anon key)
- Set strong passwords for any auth
- Use reverse proxy for external access
- Keep templates updated

### Performance

- Allocate sufficient resources
- Monitor container stats
- Use SSD for appdata if possible
- Enable caching where available

### Maintenance

- Regular backups of appdata
- Monitor logs for errors
- Keep containers updated
- Document customizations

## Support

### Getting Help

- **Template Issues:** [GitHub Issues](https://github.com/coleam00/Archon/issues)
- **Unraid Forums:** [Community Applications Thread](https://forums.unraid.net)
- **Documentation:** [Archon Docs](https://docs.archon.dev)

### Reporting Template Issues

Include:
- Template name and version
- Unraid version
- Error messages
- Docker logs
- Configuration used

## Contributing

To contribute templates:

1. Fork the repository
2. Add/modify templates in `unraid/templates/`
3. Test on Unraid 6.9+
4. Submit pull request
5. Include documentation updates

## License

Templates are provided under the same MIT License as Archon.