#!/bin/bash
set -e

# ============================================================
# Tailscale Manual Install Script for ARM / Old Debian
# Usage: bash install-tailscale.sh <headscale-url> <auth-key>
# Example:
#   bash install-tailscale.sh https://ui.vpn.smartfluiddata.com tskey-auth-xxxx
# ============================================================

HEADSCALE_URL="${1}"
AUTH_KEY="${2}"

if [ -z "$HEADSCALE_URL" ] || [ -z "$AUTH_KEY" ]; then
  echo "Usage: $0 <headscale-url> <auth-key>"
  echo "Example: $0 https://ui.vpn.smartfluiddata.com tskey-auth-xxxx"
  exit 1
fi

echo "============================================================"
echo " Tailscale Manual Installer"
echo " Headscale: $HEADSCALE_URL"
echo "============================================================"

# --- Detect architecture ---
ARCH=$(uname -m)
echo "[1/5] Detected architecture: $ARCH"

case "$ARCH" in
  armv7l|armhf)  TAILSCALE_ARCH="arm" ;;
  aarch64|arm64) TAILSCALE_ARCH="arm64" ;;
  x86_64)        TAILSCALE_ARCH="amd64" ;;
  *)
    echo "ERROR: Unsupported architecture: $ARCH"
    exit 1
    ;;
esac

echo "       Using Tailscale binary for: $TAILSCALE_ARCH"

# --- Download latest Tailscale tarball ---
echo "[2/5] Downloading Tailscale..."
DOWNLOAD_URL="https://pkgs.tailscale.com/stable/tailscale_latest_${TAILSCALE_ARCH}.tgz"
curl -fsSL "$DOWNLOAD_URL" -o /tmp/tailscale.tgz

echo "       Extracting..."
tar -xzf /tmp/tailscale.tgz -C /tmp/

# Find the extracted directory
TAILSCALE_DIR=$(find /tmp -maxdepth 1 -type d -name "tailscale_*" | head -n 1)

if [ -z "$TAILSCALE_DIR" ]; then
  echo "ERROR: Could not find extracted Tailscale directory"
  exit 1
fi

# --- Install binaries ---
echo "[3/5] Installing binaries to /usr/local/bin..."
cp "$TAILSCALE_DIR/tailscale"  /usr/local/bin/tailscale
cp "$TAILSCALE_DIR/tailscaled" /usr/local/bin/tailscaled
chmod +x /usr/local/bin/tailscale /usr/local/bin/tailscaled

echo "       Tailscale version: $(tailscale version | head -1)"

# --- Create systemd service ---
echo "[4/5] Creating systemd service..."
mkdir -p /var/lib/tailscale
mkdir -p /var/run/tailscale

cat > /etc/systemd/system/tailscaled.service << 'EOF'
[Unit]
Description=Tailscale node agent
Documentation=https://tailscale.com/kb/
After=network-pre.target NetworkManager.service systemd-resolved.service

[Service]
ExecStartPre=/bin/mkdir -p /var/lib/tailscale
ExecStartPre=/bin/mkdir -p /var/run/tailscale
ExecStart=/usr/local/bin/tailscaled --state=/var/lib/tailscale/tailscaled.state --socket=/var/run/tailscale/tailscaled.sock
ExecStopPost=/bin/rm -f /var/run/tailscale/tailscaled.sock
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable tailscaled
systemctl start tailscaled

# Wait for daemon to be ready
echo "       Waiting for tailscaled to start..."
sleep 3

# Check it's running
if ! systemctl is-active --quiet tailscaled; then
  echo "ERROR: tailscaled failed to start. Check: journalctl -u tailscaled"
  exit 1
fi

echo "       tailscaled is running!"

# --- Connect to Headscale ---
echo "[5/5] Connecting to Headscale at $HEADSCALE_URL ..."
tailscale up \
  --login-server="$HEADSCALE_URL" \
  --authkey="$AUTH_KEY" \
  --accept-routes

echo ""
echo "============================================================"
echo " Done! Verifying connection..."
echo "============================================================"
tailscale status

# Cleanup
rm -rf /tmp/tailscale.tgz "$TAILSCALE_DIR"
echo ""
echo "Install complete. This machine is now connected to your tailnet."
