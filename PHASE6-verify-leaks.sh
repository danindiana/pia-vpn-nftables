#!/bin/bash
# Phase 6: Verify No Leaks
# Runs diagnostic and manual leak tests

echo "╔════════════════════════════════════════════════════╗"
echo "║  Phase 6: Verify No Leaks                         ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
cd "$SCRIPT_DIR"

# Check if VPN is connected
if ! command -v piactl &> /dev/null; then
    echo "❌ ERROR: piactl not found"
    exit 1
fi

CONNECTION=$(piactl get connectionstate 2>&1)
if [ "$CONNECTION" != "Connected" ]; then
    echo "⚠️  VPN is not connected: $CONNECTION"
    echo "Please run Phase 5 first to establish connection"
    exit 1
fi

echo "✓ VPN is connected"
echo ""

# Run diagnostic if available
if [ -f "pia-diagnostic.sh" ]; then
    echo "Running comprehensive diagnostic..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    chmod +x pia-diagnostic.sh
    bash pia-diagnostic.sh
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
fi

# Manual leak tests
echo "Manual Leak Tests:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Get VPN IP
VPN_IP=$(piactl get vpnip 2>&1)
echo "Your VPN IP: $VPN_IP"
echo ""

# Test 1: Public IP leak test
echo "Test 1: IP Leak Check"
echo "  Querying public IP via curl..."
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "TIMEOUT")

if [ "$PUBLIC_IP" = "TIMEOUT" ]; then
    echo "  ⚠️  Could not reach API (timeout or DNS issue)"
else
    if [ "$PUBLIC_IP" = "$VPN_IP" ]; then
        echo "  ✓ Public IP matches VPN IP: $PUBLIC_IP"
        echo "    NO IP LEAK DETECTED"
    else
        echo "  ✗ IP MISMATCH!"
        echo "    VPN IP: $VPN_IP"
        echo "    Public IP: $PUBLIC_IP"
        echo "    POTENTIAL IP LEAK!"
    fi
fi
echo ""

# Test 2: DNS leak test
echo "Test 2: DNS Configuration"
echo "  Current DNS servers:"
resolvectl status | grep "Current DNS" || echo "  (Unable to query DNS status)"
echo ""
echo "  DNS leak test (if available online):"
echo "  Visit: https://www.dnsleaktest.com/"
echo ""

# Test 3: WebRTC leak test
echo "Test 3: WebRTC Leak Test"
echo "  Run in your browser:"
echo "  Visit: https://browserleaks.com/webrtc"
echo "  Should only show VPN IP, not your local IP"
echo ""

# Test 4: Kill switch test (optional)
echo "Test 4: Kill Switch Test (Advanced)"
echo "  To test kill switch:"
echo "  1. Disconnect: piactl disconnect"
echo "  2. Try to ping external host: ping -c 1 1.1.1.1"
echo "  3. Should TIMEOUT or be BLOCKED (firewall blocking)"
echo "  4. Reconnect: piactl connect"
echo ""
read -p "Do you want to test kill switch now? (y/n): " -n 1 -r KILLSWITCH_TEST
echo ""

if [[ $KILLSWITCH_TEST =~ ^[Yy]$ ]]; then
    echo "Disconnecting VPN..."
    piactl disconnect
    sleep 2
    
    echo "Testing if firewall blocks external traffic..."
    if timeout 2 ping -c 1 1.1.1.1 &>/dev/null; then
        echo "✗ WARNING: Traffic still reachable - kill switch may not be working!"
    else
        echo "✓ Kill switch working - traffic blocked when VPN is down"
    fi
    
    echo ""
    echo "Reconnecting to VPN..."
    piactl connect
    sleep 15
    echo "✓ Reconnected"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Phase 6 Complete - Leak verification done"
echo ""
echo "Next: Monitor for 24-48 hours (Phase 7)"
