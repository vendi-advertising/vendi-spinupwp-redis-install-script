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

# Save current directory before changing to temp
CURRENT_DIR=$(pwd)

cleanup() {
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

cd "$TEMP_DIR"

if [ "$VERSION" = "latest" ]; then
    info "Detecting latest release..."
    VERSION=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')

    if [ -z "$VERSION" ]; then
        error_exit "No releases found. Please create a release first with: git tag -a v1.0.0 -m \"Initial release\" && git push origin v1.0.0

Or specify a version manually:
  curl -fsSL https://raw.githubusercontent.com/${REPO}/refs/heads/main/install.sh | bash -s v1.0.0"
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

# Copy to current directory
if [[ -f "${CURRENT_DIR}/${SCRIPT_FILE}" ]]; then
    echo ""
    warn "File ${SCRIPT_FILE} already exists in current directory."
    read -p "Overwrite it? [y/N]: " overwrite
    if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
        info "Installation cancelled. Existing file not modified."
        exit 0
    fi
fi

cp "${SCRIPT_FILE}" "${CURRENT_DIR}/${SCRIPT_FILE}"
chmod +x "${CURRENT_DIR}/${SCRIPT_FILE}"

echo ""
echo "========================================"
echo "Script Downloaded and Verified!"
echo "========================================"
echo ""
success "Checksum verified! Script is authentic."
echo ""
echo "The verified script has been saved to:"
echo "  ${CURRENT_DIR}/${SCRIPT_FILE}"
echo ""
echo "To manually verify the checksum yourself:"
echo "  sha256sum ./${SCRIPT_FILE}"
echo ""
echo "Compare the output with the checksum in the README:"
echo "  https://github.com/${REPO}#sha256-checksum-verification"
echo ""
echo "To run the installation:"
echo "  sudo ./${SCRIPT_FILE}"
echo ""
echo "Or review it first:"
echo "  less ./${SCRIPT_FILE}"
echo ""
