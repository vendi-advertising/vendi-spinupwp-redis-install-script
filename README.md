# Redis Per-Site Installation Script for SpinupWP

An interactive Bash script for installing and managing isolated Redis instances on SpinupWP servers running Ubuntu 20/24.

## Overview

This script automates the process of setting up dedicated Redis instances for individual sites on a SpinupWP server. Each site gets its own Redis instance with isolated configuration, port, password, and memory allocation.

## Features

- **Interactive Site Selection**: Choose from available sites in `/sites/` directory
- **Smart Port Management**: Automatic port conflict detection and next available port suggestion
- **Secure Password Generation**: Randomly generated 32-character passwords
- **Reconfiguration Mode**: Update existing instances (change password while keeping port/memory)
- **WordPress Integration**:
  - Auto-detects WordPress installations
  - Configures `WP_REDIS_PORT` and `WP_REDIS_PASSWORD` via WP-CLI
  - Optional SpinupWP plugin installation/activation
- **Instance Overview**: Shows before/after view of all Redis instances
- **Comprehensive Validation**: Checks prerequisites, ports, memory formats, and service status
- **Color-Coded Output**: Easy-to-read success/error/warning messages

## Prerequisites

- SpinupWP server (Ubuntu 20 or 24)
- Root/sudo access
- Redis installed (`redis-server` and `redis-cli`)
- Sites in `/sites/` directory
- (Optional) WP-CLI for WordPress configuration

## Installation

### Recommended: Verified Install (One-liner)

Uses the installer script that downloads the latest release and verifies checksums:

```bash
curl -fsSL https://raw.githubusercontent.com/vendi-advertising/vendi-spinupwp-redis-install-script/refs/heads/main/install.sh | bash
```

Or specify a version:

```bash
curl -fsSL https://raw.githubusercontent.com/vendi-advertising/vendi-spinupwp-redis-install-script/refs/heads/main/install.sh | bash -s v1.0.0
```

### Manual Install with Verification

```bash
# Download latest release
VERSION=$(curl -fsSL https://api.github.com/repos/vendi-advertising/vendi-spinupwp-redis-install-script/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
curl -fsSL "https://github.com/vendi-advertising/vendi-spinupwp-redis-install-script/releases/download/${VERSION}/install-redis-per-site.sh" -o install-redis-per-site.sh
curl -fsSL "https://github.com/vendi-advertising/vendi-spinupwp-redis-install-script/releases/download/${VERSION}/checksums.txt" -o checksums.txt

# Verify checksum
sha256sum -c checksums.txt

# Run if verification passes
chmod +x install-redis-per-site.sh
sudo ./install-redis-per-site.sh
```

### Quick Install from Main (Not Recommended for Production)

⚠️ **Warning**: This skips verification and uses the latest code from main branch:

```bash
curl -fsSL https://raw.githubusercontent.com/vendi-advertising/vendi-spinupwp-redis-install-script/refs/heads/main/install-redis-per-site.sh | sudo bash
```

### Clone Repository

```bash
git clone https://github.com/vendi-advertising/vendi-spinupwp-redis-install-script.git
cd vendi-spinupwp-redis-install-script
chmod +x install-redis-per-site.sh
sudo ./install-redis-per-site.sh
```

## Usage

Run the script with sudo:

```bash
sudo ./install-redis-per-site.sh
```

The script will guide you through:

1. **Current Instance Overview**: Shows existing Redis instances
2. **Site Selection**: Choose from available sites
3. **Configuration Mode**:
   - New installation: Configure port and memory
   - Reconfigure existing: Keep port/memory, generate new password
   - Reinstall: Change all settings
4. **Confirmation**: Review settings before proceeding
5. **WordPress Setup** (if detected):
   - Configure wp-config.php with Redis settings
   - Optional SpinupWP plugin installation
6. **Final Summary**: Connection details and instance overview

## Configuration Details

### Default Settings

- **Port Range**: 6380-6400 (auto-detects next available)
- **Default Memory**: 256M
- **Password**: Auto-generated 32-character string
- **Config Location**: `/etc/redis/sites/overrides.{site}.conf`
- **Service Name**: `redis-server-{site}.service`

### File Locations

- Main config: `/etc/redis/redis.{site}.conf`
- Overrides: `/etc/redis/sites/overrides.{site}.conf`
- Service file: `/etc/systemd/system/redis-server-{site}.service`
- Log file: `/var/log/redis/redis-server-{site}.log`
- PID file: `/var/run/redis/redis-server-{site}.pid`
- Database: `/var/lib/redis/dump-{site}.rdb`

## Managing Redis Instances

### Service Commands

```bash
# Check status
sudo systemctl status redis-server-{site}

# Start/Stop/Restart
sudo systemctl start redis-server-{site}
sudo systemctl stop redis-server-{site}
sudo systemctl restart redis-server-{site}

# View logs
sudo journalctl -u redis-server-{site} -f
```

### Testing Connection

```bash
redis-cli -p {port} -a "{password}" ping
# Should return: PONG
```

## WordPress Integration

The script automatically:

1. Detects WordPress installations by checking:
   - Nginx configuration for web root
   - Standard `~/files/` location
2. Sets wp-config.php constants via WP-CLI:
   ```php
   define('WP_REDIS_PORT', 6380);
   define('WP_REDIS_PASSWORD', 'your-password');
   ```
3. Optionally installs/activates SpinupWP plugin for Redis object caching

## Troubleshooting

### Redis won't start

```bash
# Check logs
sudo journalctl -u redis-server-{site} -n 50

# Verify config
sudo redis-server /etc/redis/redis.{site}.conf --test-memory 1
```

### Port already in use

The script auto-detects port conflicts. If needed, manually check:

```bash
ss -tuln | grep :{port}
```

### WordPress not detecting Redis

Ensure the SpinupWP plugin or another Redis object cache plugin is installed and active:

```bash
wp plugin list --status=active
```

## Security Notes

- Passwords are auto-generated and displayed once (save them!)
- Config files have restricted permissions (640)
- Each instance is isolated with `requirepass` authentication
- Uses `allkeys-lru` eviction policy to prevent memory overflow

## Uninstalling an Instance

To remove a Redis instance:

```bash
# Stop and disable service
sudo systemctl stop redis-server-{site}
sudo systemctl disable redis-server-{site}

# Remove files
sudo rm /etc/redis/redis.{site}.conf
sudo rm /etc/redis/sites/overrides.{site}.conf
sudo rm /etc/systemd/system/redis-server-{site}.service
sudo rm /var/log/redis/redis-server-{site}.log

# Reload systemd
sudo systemctl daemon-reload
```

## Credits

Based on [Chris Haas's original post](https://community.spinupwp.com/c/peer-to-peer-help/redis-max-memory-per-site#comment_wrapper_43145465) in the SpinupWP community forums.

## License

MIT License - Feel free to use and modify as needed.

## Contributing

Issues and pull requests welcome! Please test on a non-production server first.
