#!/bin/bash
# Phase 4: Install nftables Kill Switch
# Wrapper script for nftables-pia-setup.sh with proper execution

echo "╔════════════════════════════════════════════════════╗"
echo "║  Phase 4: Install nftables Kill Switch            ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Ensure we're in the script directory
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
cd "$SCRIPT_DIR"

# Check if nftables-pia-setup.sh exists
if [ ! -f "nftables-pia-setup.sh" ]; then
    echo "❌ ERROR: nftables-pia-setup.sh not found in $SCRIPT_DIR"
    exit 1
fi

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  This script needs to be run with sudo"
    echo "Usage: sudo bash PHASE4-nftables-install.sh"
    exit 1
fi

echo "Running nftables PIA setup..."
echo ""

# Make setup script executable and run it
chmod +x nftables-pia-setup.sh
bash nftables-pia-setup.sh

echo ""
echo "✅ Phase 4 Complete - nftables kill switch installed"
echo ""
echo "Next: Run Phase 5 to test VPN connection"
