#!/usr/bin/env bash

#############################################
# Redis Per-Site Installer with Verification
# Downloads and verifies the installation script
#############################################

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

error_exit() {
    echo -e "${RED}ERROR: $1${NC}" >&2
    exit 1
}

info() {
    echo -e "${BLUE}INFO: $1${NC}"
}

success() {
    echo -e "${GREEN}SUCCESS: $1${NC}"
}

# Configuration
REPO="vendi-advertising/vendi-spinupwp-redis-install-script"
VERSION="${1:-latest}"  # Accept version as argument, default to latest
TEMP_DIR=$(mktemp -d)
SCRIPT_FILE="install-redis-per-site.sh"
CHECKSUM_FILE="checksums.txt"

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$TEMP_DIR"

if [ "$VERSION" = "latest" ]; then
    info "Detecting latest release..."
    VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$VERSION" ]; then
        error_exit "Could not detect latest version. Please specify a version: ./install.sh v1.0.0"
    fi

    success "Latest version: $VERSION"
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}"

info "Downloading script and checksums..."

# Download files
if ! curl -fsSL "${DOWNLOAD_URL}/${SCRIPT_FILE}" -o "${SCRIPT_FILE}"; then
    error_exit "Failed to download script. Check version: $VERSION"
fi

if ! curl -fsSL "${DOWNLOAD_URL}/${CHECKSUM_FILE}" -o "${CHECKSUM_FILE}"; then
    error_exit "Failed to download checksums"
fi

success "Downloaded files"

# Verify checksum
info "Verifying checksum..."
if sha256sum -c "${CHECKSUM_FILE}" --quiet 2>/dev/null; then
    success "Checksum verified! Script is authentic."
else
    error_exit "Checksum verification failed! The script may be corrupted or tampered with."
fi

# Make executable
chmod +x "${SCRIPT_FILE}"

echo ""
echo "========================================"
echo "Script ready to run!"
echo "========================================"
echo ""
echo "The script has been verified and is ready to install."
echo ""
echo "To run it now:"
echo "  sudo $TEMP_DIR/${SCRIPT_FILE}"
echo ""
echo "Or copy to current directory and run:"
echo "  cp $TEMP_DIR/${SCRIPT_FILE} ./${SCRIPT_FILE}"
echo "  sudo ./${SCRIPT_FILE}"
echo ""
read -p "Run the installation script now? [Y/n]: " run_now

if [[ ! "$run_now" =~ ^[Nn]$ ]]; then
    echo ""
    exec sudo "$TEMP_DIR/${SCRIPT_FILE}"
else
    info "Installation cancelled. Script is available at: $TEMP_DIR/${SCRIPT_FILE}"

    # Don't cleanup if user declined
    trap - EXIT
fi
