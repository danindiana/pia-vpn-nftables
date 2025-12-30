#!/bin/bash
# PIA Configuration Validator & Fixer
# Verifies proper configuration method for firewall bypass

set -e

echo "=== PIA Configuration Validator ==="
echo ""

# Check if PIA is installed
if ! command -v piactl &> /dev/null; then
    echo "❌ ERROR: piactl not found. Is PIA installed?"
    exit 1
fi

# Check current firewall backend
echo "1. Checking firewall backend..."
IPTABLES_VERSION=$(iptables --version 2>&1)
echo "   Current: $IPTABLES_VERSION"

if echo "$IPTABLES_VERSION" | grep -q "nf_tables"; then
    echo "   ⚠️  WARNING: Using iptables-nft (incompatible with PIA v3.7.0)"
    USING_NFTABLES=true
else
    echo "   ✓ Using iptables-legacy"
    USING_NFTABLES=false
fi
echo ""

# Check PIA settings
echo "2. Checking current PIA settings..."
KILLSWITCH=$(piactl get killswitch 2>/dev/null || echo "unknown")
ALLOWLAN=$(piactl get allowlan 2>/dev/null || echo "unknown")
echo "   Kill Switch: $KILLSWITCH"
echo "   Allow LAN: $ALLOWLAN"
echo ""

# Verify config file locations
echo "3. Locating PIA configuration files..."
for config_path in \
    "/opt/piavpn/etc/client-settings.json" \
    "$HOME/.config/pia/client-settings.json" \
    "/etc/pia/settings.json"; do
    
    if [ -f "$config_path" ]; then
        echo "   ✓ Found: $config_path"
        # Show relevant settings
        if command -v jq &> /dev/null; then
            echo "     Kill switch setting: $(jq -r '.killswitch // "not set"' "$config_path" 2>/dev/null)"
        fi
    fi
done
echo ""

# Recommend configuration
echo "4. Recommended Configuration Method:"
echo ""
if [ "$USING_NFTABLES" = true ]; then
    echo "   Since you're using nftables, configure PIA as follows:"
    echo ""
    echo "   # Disable PIA's built-in kill switch (it won't work with nftables)"
    echo "   piactl set killswitch off"
    echo ""
    echo "   # Allow LAN traffic (for local development)"
    echo "   piactl set allowlan true"
    echo ""
    echo "   # Apply settings"
    echo "   piactl applysettings"
    echo ""
    echo "   Then implement external nftables kill switch (see nftables-pia-setup.sh)"
else
    echo "   You can use PIA's built-in kill switch:"
    echo "   piactl set killswitch auto"
fi

echo ""
echo "=== Configuration Check Complete ==="
