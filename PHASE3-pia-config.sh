#!/bin/bash
# Phase 3: Configure PIA Settings
# Disables PIA's built-in firewall and enables LAN access

echo "╔════════════════════════════════════════════════════╗"
echo "║  Phase 3: Configure PIA Settings                  ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Check if piactl is available
if ! command -v piactl &> /dev/null; then
    echo "❌ ERROR: piactl not found - PIA may not be installed"
    exit 1
fi

echo "Current PIA configuration:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Kill Switch: $(piactl get killswitch 2>&1)"
echo "Allow LAN: $(piactl get allowlan 2>&1)"
echo "Connection State: $(piactl get connectionstate 2>&1)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Configuring PIA for nftables compatibility..."
echo ""

# Disable PIA's firewall module
echo "1. Disabling PIA's built-in kill switch..."
if piactl set killswitch off &>/dev/null; then
    echo "   ✓ Kill switch disabled"
else
    echo "   ⚠️  Kill switch setting failed (may already be configured)"
fi

# Enable LAN access
echo "2. Enabling LAN access..."
if piactl set allowlan true &>/dev/null; then
    echo "   ✓ LAN access enabled"
else
    echo "   ⚠️  LAN access setting failed (may already be configured)"
fi

# Apply settings
echo "3. Applying settings..."
if piactl applysettings &>/dev/null; then
    echo "   ✓ Settings applied"
else
    echo "   ⚠️  Apply settings failed (settings may have been applied)"
fi

sleep 2

# Verify configuration
echo ""
echo "Updated PIA configuration:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Kill Switch: $(piactl get killswitch 2>&1)"
echo "Allow LAN: $(piactl get allowlan 2>&1)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "✅ Phase 3 Complete - PIA configured for nftables"
echo ""
echo "Next: Run Phase 4 to install nftables kill switch rules"
