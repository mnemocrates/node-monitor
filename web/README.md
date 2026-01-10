# Web Display for Node Monitor

This directory contains example HTML files for displaying your node-monitor data on a public-facing website.

## Overview

Node-monitor exports two types of JSON data:
- **status.json** - Real-time check results from all monitoring checks
- **nodecard.json** - Static node information (alias, pubkey, URIs, capabilities)

These HTML files provide simple, static web pages that fetch and display this JSON data using JavaScript.

## Files

- **status.html.example** - Displays current monitoring status with color-coded checks
- **nodecard.html.example** - Displays Lightning node information and capabilities
- **deploy-web.sh.example** - Script to deploy HTML files to your web server

## Quick Start

### 1. Customize HTML Files

Copy the example files and customize them for your setup:

```bash
cd web/
cp status.html.example status.html
cp nodecard.html.example nodecard.html
```

Edit each HTML file and update the JSON URLs:

```javascript
// Update this line in each file
const JSON_URL = 'https://your-domain.com/path/to/status.json';
```

Optionally customize:
- Page title and header
- CSS styling (colors, fonts, layout)
- Refresh interval
- Check grouping/display logic

### 2. Deploy to Web Server

**Option A: Manual Deployment**

Copy the HTML files to your web server manually:

```bash
scp status.html user@your-server:/var/www/html/status/index.html
scp nodecard.html user@your-server:/var/www/html/nodecard/index.html
```

**Option B: Automated Deployment**

Use the provided deployment script:

```bash
cp deploy-web.sh.example deploy-web.sh
chmod +x deploy-web.sh

# Configure deployment in config.sh (see Configuration section)
./deploy-web.sh
```

### 3. Configure Web Server

Ensure your web server (nginx/apache) is configured to:
- Serve static HTML files
- Serve the JSON files exported by node-monitor
- Set appropriate CORS headers if JSON and HTML are on different domains

**Example nginx configuration:**

```nginx
server {
    listen 80;
    server_name your-domain.com;
    
    root /var/www/html;
    index index.html;
    
    location /status/ {
        try_files $uri $uri/ =404;
    }
    
    location /nodecard/ {
        try_files $uri $uri/ =404;
    }
    
    # JSON files
    location ~ \.json$ {
        add_header Access-Control-Allow-Origin *;
        add_header Cache-Control "no-cache, must-revalidate";
    }
}
```

## Configuration

The `deploy-web.sh` script reads configuration from `config.sh`. Add these settings:

```bash
# Web deployment settings
WEB_DEPLOY_ENABLED="true"
WEB_DEPLOY_METHOD="scp"              # scp or rsync
WEB_DEPLOY_TRANSPORT="torsocks"      # torsocks or direct

# Status page deployment
WEB_STATUS_SOURCE="web/status.html"
WEB_STATUS_TARGET="user@remote-host:/var/www/html/status/index.html"

# Nodecard page deployment  
WEB_NODECARD_SOURCE="web/nodecard.html"
WEB_NODECARD_TARGET="user@remote-host:/var/www/html/nodecard/index.html"

# SSH identity for scp
WEB_DEPLOY_SCP_IDENTITY="${HOME}/.ssh/id_ed25519"

# Torsocks binary (if using tor)
TORSOCKS_BIN="/usr/bin/torsocks"
```

## Deployment Workflow

1. **Initial setup**: Customize HTML files, deploy once manually or with script
2. **JSON updates**: Automatic via `export-status.sh` and `export-nodecard.sh` (run by cron)
3. **HTML updates**: Deploy manually or with `deploy-web.sh` when you modify the display

The HTML files rarely change, so manual deployment is usually sufficient. Use `deploy-web.sh` if you frequently update styling or add features.

## Security Considerations

### Public Data
These pages display **public information**:
- Check status (OK/WARN/CRIT) and messages
- Node alias, pubkey, and connection URIs
- Channel counts and capabilities

### Private Data NOT Exposed
- Specific channel details (peers, balances, fees)
- Bitcoin/LND authentication credentials
- System internals (disk usage, memory, temperature)
- Alert destinations (email, Signal, ntfy)

### Recommendations
- Host on a separate server from your Lightning node
- Use HTTPS with valid certificates
- Consider rate limiting to prevent DoS
- Monitor access logs for abuse
- Don't expose the full `check-status` directory, only the merged JSON

## Customization

### Styling

Both HTML files use embedded CSS for easy customization. Key elements:

**Status colors:**
```css
.status-ok { color: #28a745; }
.status-warn { color: #ffc107; }
.status-crit { color: #dc3545; }
```

**Layout:**
```css
.container { max-width: 1200px; margin: 0 auto; }
.check-grid { display: grid; gap: 1rem; }
```

### JavaScript

The pages use vanilla JavaScript with fetch API. Key functions:

```javascript
async function fetchData(url)  // Fetch JSON
function updateDisplay(data)   // Update DOM
function formatTimestamp(ts)   // Format dates
setInterval(fetchData, 30000)  // Auto-refresh
```

### Adding Features

Common enhancements:
- Dark mode toggle
- Filter checks by category
- Historical trend graphs (requires storing past data)
- Alert history display
- Mobile-responsive design improvements

## Troubleshooting

**JSON not loading:**
- Check browser console for CORS errors
- Verify JSON URL is correct and accessible
- Ensure web server has CORS headers configured

**Stale data:**
- Check that `export-status.sh` is running via cron
- Verify JSON files are being updated on the server
- Check browser cache (disable during testing)

**Page not updating:**
- Check JavaScript console for errors
- Verify refresh interval in code
- Test manual reload

**Deployment fails:**
- Verify SSH keys and permissions
- Check torsocks configuration if using Tor
- Test scp/rsync command manually

## Examples

See example deployments:
- Status page: `https://your-domain.com/status/`
- Node card: `https://your-domain.com/nodecard/`

## Support

For issues or questions:
1. Check the main node-monitor README.md
2. Review export-status.sh and export-nodecard.sh configuration
3. Test JSON endpoints directly in browser
4. Check web server logs

## License

These HTML files follow the same license as the node-monitor project.
