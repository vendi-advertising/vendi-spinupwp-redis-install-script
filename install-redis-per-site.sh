#!/usr/bin/env bash

set -euo pipefail

#############################################
# Redis Per-Site Instance Installation Script
# For SpinupWP-based Ubuntu 20/24 servers
#############################################

## Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

## Helper functions
error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

warn() {
    echo -e "${YELLOW}WARNING: $1${NC}" >&2
}

info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

## Function to display Redis instances
show_redis_instances() {
    local title="$1"
    echo ""
    echo "========================================"
    echo "${title}"
    echo "========================================"

    # Find all site-specific Redis override files
    if compgen -G "${REDIS_CONFIG_SITE_ROOT}/overrides.*.conf" > /dev/null 2>&1; then
        echo ""
        printf "%-40s %-10s %-15s %-10s\n" "SITE" "PORT" "MAX MEMORY" "STATUS"
        printf "%-40s %-10s %-15s %-10s\n" "----" "----" "----------" "------"

        for override_file in ${REDIS_CONFIG_SITE_ROOT}/overrides.*.conf; do
            # Extract site name from filename
            site=$(basename "$override_file" | sed 's/overrides\.\(.*\)\.conf/\1/')

            # Extract port and memory
            port=$(grep "^port " "$override_file" 2>/dev/null | awk '{print $2}')
            memory=$(grep "^maxmemory " "$override_file" 2>/dev/null | awk '{print $2}')

            # Check service status
            if systemctl is-active --quiet redis-server-${site}.service 2>/dev/null; then
                status="${GREEN}running${NC}"
            else
                status="${RED}stopped${NC}"
            fi

            printf "%-40s %-10s %-15s " "$site" "${port:-unknown}" "${memory:-unknown}"
            echo -e "$status"
        done
    else
        echo ""
        echo "No Redis instances found."
    fi
    echo ""
}

## Check if running as root
if [[ $EUID -ne 0 ]]; then
    error_exit "This script must be run as root. Please use sudo."
fi

## Set up helper variables
SITES_ROOT=/sites
REDIS_CONFIG_ROOT=/etc/redis
REDIS_CONFIG_SITE_ROOT=/etc/redis/sites
REDIS_PRIMARY_CONFIG=${REDIS_CONFIG_ROOT}/redis.conf
SYSTEMD_SERVICE_SOURCE=/lib/systemd/system/redis-server.service

## Validate prerequisites
info "Checking prerequisites..."

if [[ ! -d "${SITES_ROOT}" ]]; then
    error_exit "Sites directory ${SITES_ROOT} does not exist. Is this a SpinupWP server?"
fi

if [[ ! -f "${REDIS_PRIMARY_CONFIG}" ]]; then
    error_exit "Redis primary config ${REDIS_PRIMARY_CONFIG} not found. Is Redis installed?"
fi

if [[ ! -f "${SYSTEMD_SERVICE_SOURCE}" ]]; then
    error_exit "Redis systemd service ${SYSTEMD_SERVICE_SOURCE} not found. Is Redis installed?"
fi

if ! command -v redis-cli &> /dev/null; then
    error_exit "redis-cli command not found. Is Redis installed?"
fi

if ! id redis &> /dev/null; then
    error_exit "Redis user does not exist. Is Redis properly installed?"
fi

success "All prerequisites met."

## Show current Redis instances
show_redis_instances "Current Redis Instances"

## Get list of available sites
info "Scanning for SpinupWP sites..."
mapfile -t AVAILABLE_SITES < <(find "${SITES_ROOT}" -maxdepth 1 -mindepth 1 -type d -printf '%f\n' | sort)

if [[ ${#AVAILABLE_SITES[@]} -eq 0 ]]; then
    error_exit "No sites found in ${SITES_ROOT}"
fi

success "Found ${#AVAILABLE_SITES[@]} site(s)."
echo ""

## Display available sites
echo "Available sites:"
for i in "${!AVAILABLE_SITES[@]}"; do
    echo "  $((i+1)). ${AVAILABLE_SITES[$i]}"
done
echo ""

## Prompt for site selection
while true; do
    read -p "Select site number [1-${#AVAILABLE_SITES[@]}]: " site_selection
    if [[ "$site_selection" =~ ^[0-9]+$ ]] && \
       [[ $site_selection -ge 1 ]] && \
       [[ $site_selection -le ${#AVAILABLE_SITES[@]} ]]; then
        SITE_NAME="${AVAILABLE_SITES[$((site_selection-1))]}"
        break
    else
        warn "Invalid selection. Please enter a number between 1 and ${#AVAILABLE_SITES[@]}."
    fi
done

info "Selected site: ${SITE_NAME}"
echo ""

## Check if Redis instance already exists for this site
REDIS_INSTANCE_CONFIG_MAIN_FILE=${REDIS_CONFIG_ROOT}/redis.${SITE_NAME}.conf
REDIS_INSTANCE_CONFIG_OVERRIDES=${REDIS_CONFIG_SITE_ROOT}/overrides.${SITE_NAME}.conf
SYSTEMD_INSTANCE_SERVICE_FILE=/etc/systemd/system/redis-server-${SITE_NAME}.service

RECONFIGURE_MODE=false
EXISTING_PORT=""
EXISTING_MEMORY=""

if [[ -f "${REDIS_INSTANCE_CONFIG_OVERRIDES}" ]]; then
    warn "Redis instance for ${SITE_NAME} already exists."

    # Extract existing configuration
    EXISTING_PORT=$(grep "^port " "${REDIS_INSTANCE_CONFIG_OVERRIDES}" | awk '{print $2}')
    EXISTING_MEMORY=$(grep "^maxmemory " "${REDIS_INSTANCE_CONFIG_OVERRIDES}" | awk '{print $2}')

    echo ""
    echo "Current configuration:"
    echo "  Port:       ${EXISTING_PORT:-unknown}"
    echo "  Max Memory: ${EXISTING_MEMORY:-unknown}"
    echo ""

    echo "What would you like to do?"
    echo "  1. Reconfigure (keep port/memory, change password only)"
    echo "  2. Reinstall (change all settings)"
    echo "  3. Cancel"
    read -p "Select option [1-3]: " reconfig_option

    case "$reconfig_option" in
        1)
            RECONFIGURE_MODE=true
            info "Reconfiguration mode: Will keep existing port and memory settings."
            ;;
        2)
            info "Reinstall mode: You can change all settings."
            ;;
        3)
            info "Operation cancelled."
            exit 0
            ;;
        *)
            error_exit "Invalid option selected."
            ;;
    esac
    echo ""
fi

## Function to check if port is in use
is_port_in_use() {
    local port=$1
    # Check if port is in use by any process
    if ss -tuln | grep -q ":${port} "; then
        return 0  # Port is in use
    fi
    # Check if port is already configured in another Redis instance
    if grep -q "^port ${port}$" ${REDIS_CONFIG_SITE_ROOT}/overrides.*.conf 2>/dev/null; then
        return 0  # Port is in use
    fi
    return 1  # Port is free
}

## Function to suggest next available port
suggest_next_port() {
    local start_port=6380
    local port=$start_port
    while is_port_in_use $port; do
        ((port++))
        if [[ $port -gt 6400 ]]; then
            error_exit "Could not find available port between 6380-6400"
        fi
    done
    echo $port
}

## Prompt for Redis port (skip if reconfiguring)
if [[ "$RECONFIGURE_MODE" == true ]]; then
    SITE_REDIS_PORT="${EXISTING_PORT}"
    info "Using existing port: ${SITE_REDIS_PORT}"
    echo ""
else
    DEFAULT_PORT=$(suggest_next_port)
    while true; do
        read -p "Redis port [default: ${DEFAULT_PORT}]: " SITE_REDIS_PORT
        SITE_REDIS_PORT=${SITE_REDIS_PORT:-$DEFAULT_PORT}

        if ! [[ "$SITE_REDIS_PORT" =~ ^[0-9]+$ ]] || \
           [[ $SITE_REDIS_PORT -lt 1024 ]] || \
           [[ $SITE_REDIS_PORT -gt 65535 ]]; then
            warn "Invalid port. Please enter a number between 1024 and 65535."
            continue
        fi

        if is_port_in_use $SITE_REDIS_PORT; then
            warn "Port ${SITE_REDIS_PORT} is already in use. Please choose another port."
            continue
        fi

        break
    done

    info "Using port: ${SITE_REDIS_PORT}"
    echo ""
fi

## Prompt for max memory (skip if reconfiguring)
if [[ "$RECONFIGURE_MODE" == true ]]; then
    SITE_REDIS_MAX_MEMORY="${EXISTING_MEMORY}"
    info "Using existing max memory: ${SITE_REDIS_MAX_MEMORY}"
    echo ""
else
    read -p "Maximum memory (e.g., 256M, 512M, 1G) [default: 256M]: " SITE_REDIS_MAX_MEMORY
    SITE_REDIS_MAX_MEMORY=${SITE_REDIS_MAX_MEMORY:-256M}

    # Validate memory format
    if ! [[ "$SITE_REDIS_MAX_MEMORY" =~ ^[0-9]+[MmGg]$ ]]; then
        error_exit "Invalid memory format. Use format like 256M or 1G"
    fi

    info "Using max memory: ${SITE_REDIS_MAX_MEMORY}"
    echo ""
fi

## Generate random password
info "Generating secure random password..."
SITE_REDIS_PASSWORD=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)

if [[ -z "$SITE_REDIS_PASSWORD" ]]; then
    error_exit "Failed to generate password"
fi

success "Password generated."
echo ""

## Summary before installation
echo "================================"
if [[ "$RECONFIGURE_MODE" == true ]]; then
    echo "Reconfiguration Summary"
else
    echo "Installation Summary"
fi
echo "================================"
echo "Site Name:    ${SITE_NAME}"
echo "Port:         ${SITE_REDIS_PORT}"
echo "Max Memory:   ${SITE_REDIS_MAX_MEMORY}"
echo "Password:     ${SITE_REDIS_PASSWORD} (new)"
echo "================================"
echo ""

if [[ "$RECONFIGURE_MODE" == true ]]; then
    read -p "Proceed with reconfiguration? [Y/n]: " proceed
else
    read -p "Proceed with installation? [Y/n]: " proceed
fi

if [[ "$proceed" =~ ^[Nn]$ ]]; then
    info "Operation cancelled."
    exit 0
fi

echo ""
if [[ "$RECONFIGURE_MODE" == true ]]; then
    info "Starting reconfiguration..."
else
    info "Starting installation..."
fi

## Create the sites folder if it doesn't exist
mkdir -p ${REDIS_CONFIG_SITE_ROOT}

## Clone the stock config (skip if reconfiguring)
if [[ "$RECONFIGURE_MODE" == true ]]; then
    info "Updating Redis configuration..."
else
    info "Creating Redis configuration..."
    cp ${REDIS_PRIMARY_CONFIG} ${REDIS_INSTANCE_CONFIG_MAIN_FILE}
fi

## Set our overrides
cat > ${REDIS_INSTANCE_CONFIG_OVERRIDES} <<EOL
port ${SITE_REDIS_PORT}
pidfile /var/run/redis/redis-server-${SITE_NAME}.pid
logfile /var/log/redis/redis-server-${SITE_NAME}.log
dbfilename dump-${SITE_NAME}.rdb
maxmemory ${SITE_REDIS_MAX_MEMORY}
maxmemory-policy allkeys-lru
requirepass "${SITE_REDIS_PASSWORD}"
EOL

## Include our overrides at the end
cat >> ${REDIS_INSTANCE_CONFIG_MAIN_FILE} <<EOL

include ${REDIS_INSTANCE_CONFIG_OVERRIDES}

EOL

## Clone the stock service (skip if reconfiguring and service exists)
if [[ "$RECONFIGURE_MODE" == true ]] && [[ -f "${SYSTEMD_INSTANCE_SERVICE_FILE}" ]]; then
    info "Using existing systemd service..."
else
    info "Creating systemd service..."
    cp ${SYSTEMD_SERVICE_SOURCE} ${SYSTEMD_INSTANCE_SERVICE_FILE}

    ## Find-and-replace with site-specific values
    sed -i \
        -e "s#Description=Advanced key-value store#Description=Advanced key-value store for ${SITE_NAME}#" \
        -e "s#ExecStart=/usr/bin/redis-server /etc/redis/redis.conf#ExecStart=/usr/bin/redis-server ${REDIS_INSTANCE_CONFIG_MAIN_FILE}#" \
        -e "s#PIDFile=/run/redis/redis-server.pid#PIDFile=/run/redis/redis-server-${SITE_NAME}.pid#" \
        -e "s#Alias=redis.service#Alias=redis-${SITE_NAME}.service#" \
        ${SYSTEMD_INSTANCE_SERVICE_FILE}
fi

## Set required permissions
info "Setting permissions..."
chown redis:redis ${REDIS_INSTANCE_CONFIG_MAIN_FILE}
chown redis:redis ${REDIS_INSTANCE_CONFIG_OVERRIDES}
chown root:root ${SYSTEMD_INSTANCE_SERVICE_FILE}
chmod 640 ${REDIS_INSTANCE_CONFIG_OVERRIDES}

## Reload systemd
info "Reloading systemd daemon..."
systemctl daemon-reload

## Enable and start/restart the service
if [[ "$RECONFIGURE_MODE" == true ]]; then
    info "Restarting Redis service..."
    systemctl restart redis-server-${SITE_NAME}.service
else
    info "Enabling and starting Redis service..."
    systemctl enable redis-server-${SITE_NAME}.service
    systemctl start redis-server-${SITE_NAME}.service
fi

## Wait a moment for service to start
sleep 2

## Check service status
if ! systemctl is-active --quiet redis-server-${SITE_NAME}.service; then
    error_exit "Redis service failed to start. Check: journalctl -u redis-server-${SITE_NAME}.service"
fi

## Test connection
info "Testing Redis connection..."
if redis-cli -a "${SITE_REDIS_PASSWORD}" -p ${SITE_REDIS_PORT} ping 2>/dev/null | grep -q "PONG"; then
    success "Redis instance is running and responding!"
else
    error_exit "Redis instance is running but not responding to ping. Check logs: journalctl -u redis-server-${SITE_NAME}.service"
fi

echo ""

## Check if this is a WordPress site and configure it
SITE_PATH="${SITES_ROOT}/${SITE_NAME}"

info "Checking if site is WordPress..."

# Get the owner of the site directory
SITE_USER=$(stat -c '%U' "${SITE_PATH}" 2>/dev/null)

if [[ -z "${SITE_USER}" ]] || ! id "${SITE_USER}" &> /dev/null; then
    warn "Could not determine site user. Skipping WordPress configuration."
else
    info "Site user: ${SITE_USER}"

    # Try to detect WordPress root using nginx config
    WP_ROOT=""
    NGINX_ROOT=$(nginx -T 2>/dev/null | grep -A 20 "server_name.*${SITE_NAME}" | grep -m1 "^\s*root " | awk '{print $2}' | tr -d ';')

    if [[ -n "${NGINX_ROOT}" ]] && [[ -f "${NGINX_ROOT}/wp-config.php" ]]; then
        WP_ROOT="${NGINX_ROOT}"
        info "Detected WordPress root from nginx: ${WP_ROOT}"
    elif sudo -u "${SITE_USER}" bash -c "[[ -f ~/files/wp-config.php ]]" 2>/dev/null; then
        WP_ROOT="~/files"
        info "Using standard WordPress location: ~/files"
    else
        info "Could not locate WordPress installation. Skipping WordPress configuration."
    fi

    # Check if WP-CLI is available and site is WordPress
    if [[ -n "${WP_ROOT}" ]] && sudo -u "${SITE_USER}" bash -c "cd ${WP_ROOT} && wp core version" &> /dev/null; then
        WP_VERSION=$(sudo -u "${SITE_USER}" bash -c "cd ${WP_ROOT} && wp core version 2>/dev/null")
        success "WordPress ${WP_VERSION} detected!"

        echo ""
        read -p "Configure WordPress to use this Redis instance? [Y/n]: " configure_wp
        if [[ ! "$configure_wp" =~ ^[Nn]$ ]]; then
            info "Configuring WordPress Redis settings..."

            # Set Redis port
            if sudo -u "${SITE_USER}" bash -c "cd ${WP_ROOT} && wp config set WP_REDIS_PORT ${SITE_REDIS_PORT} --raw" 2>/dev/null; then
                success "Set WP_REDIS_PORT to ${SITE_REDIS_PORT}"
            else
                warn "Failed to set WP_REDIS_PORT (this may be normal if wp-config.php is not writable)"
            fi

            # Set Redis password
            if sudo -u "${SITE_USER}" bash -c "cd ${WP_ROOT} && wp config set WP_REDIS_PASSWORD '${SITE_REDIS_PASSWORD}'" 2>/dev/null; then
                success "Set WP_REDIS_PASSWORD"
            else
                warn "Failed to set WP_REDIS_PASSWORD (this may be normal if wp-config.php is not writable)"
            fi

            echo ""
            success "WordPress has been configured to use this Redis instance."

            # Check if SpinupWP plugin is installed
            if sudo -u "${SITE_USER}" bash -c "cd ${WP_ROOT} && wp plugin is-installed spinupwp" 2>/dev/null; then
                # Check if it's active
                if sudo -u "${SITE_USER}" bash -c "cd ${WP_ROOT} && wp plugin is-active spinupwp" 2>/dev/null; then
                    info "SpinupWP plugin is already installed and active."
                else
                    info "SpinupWP plugin is installed but not active."
                    read -p "Activate SpinupWP plugin (enables Redis object cache)? [y/N]: " activate_plugin
                    if [[ "$activate_plugin" =~ ^[Yy]$ ]]; then
                        if sudo -u "${SITE_USER}" bash -c "cd ${WP_ROOT} && wp plugin activate spinupwp" 2>/dev/null; then
                            success "SpinupWP plugin activated."
                        else
                            warn "Failed to activate SpinupWP plugin."
                        fi
                    fi
                fi
            else
                info "SpinupWP plugin is not installed."
                read -p "Install and activate SpinupWP plugin (enables Redis object cache)? [y/N]: " install_plugin
                if [[ "$install_plugin" =~ ^[Yy]$ ]]; then
                    if sudo -u "${SITE_USER}" bash -c "cd ${WP_ROOT} && wp plugin install spinupwp --activate" 2>/dev/null; then
                        success "SpinupWP plugin installed and activated."
                    else
                        warn "Failed to install SpinupWP plugin."
                    fi
                else
                    info "You may need to install/activate a Redis object cache plugin manually."
                fi
            fi
        else
            info "Skipped WordPress configuration."
        fi
    else
        info "Site is not WordPress or WP-CLI is not available. Skipping WordPress configuration."
    fi
fi

echo ""
echo "========================================"
if [[ "$RECONFIGURE_MODE" == true ]]; then
    echo "Redis Instance Successfully Reconfigured!"
else
    echo "Redis Instance Successfully Installed!"
fi
echo "========================================"
echo ""
echo "Connection Details:"
echo "-------------------"
echo "Host:     127.0.0.1 (or localhost)"
echo "Port:     ${SITE_REDIS_PORT}"
echo "Password: ${SITE_REDIS_PASSWORD}"
echo ""
echo "Service Management:"
echo "-------------------"
echo "Status:  sudo systemctl status redis-server-${SITE_NAME}"
echo "Stop:    sudo systemctl stop redis-server-${SITE_NAME}"
echo "Start:   sudo systemctl start redis-server-${SITE_NAME}"
echo "Restart: sudo systemctl restart redis-server-${SITE_NAME}"
echo "Logs:    sudo journalctl -u redis-server-${SITE_NAME} -f"
echo ""
echo "Configuration Files:"
echo "--------------------"
echo "Main:      ${REDIS_INSTANCE_CONFIG_MAIN_FILE}"
echo "Overrides: ${REDIS_INSTANCE_CONFIG_OVERRIDES}"
echo "Service:   ${SYSTEMD_INSTANCE_SERVICE_FILE}"
echo ""
echo "IMPORTANT: Save the password above - it will not be displayed again!"
echo "========================================"

## Show updated Redis instances
show_redis_instances "All Redis Instances"
