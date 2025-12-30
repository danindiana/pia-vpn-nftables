#!/bin/bash
# Phase 5: Test VPN Connection
# Verifies PIA can connect and retrieve VPN IP

echo "╔════════════════════════════════════════════════════╗"
echo "║  Phase 5: Test VPN Connection                     ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

# Check if piactl is available
if ! command -v piactl &> /dev/null; then
    echo "❌ ERROR: piactl not found"
    exit 1
fi

echo "Checking current connection state..."
CONNECTION=$(piactl get connectionstate 2>&1)
echo "Current state: $CONNECTION"
echo ""

if [ "$CONNECTION" = "Connected" ]; then
    echo "✓ Already connected to VPN"
    VPN_IP=$(piactl get vpnip 2>&1)
    echo "  VPN IP: $VPN_IP"
else
    echo "Attempting to connect to VPN..."
    echo ""
    
    # Try to connect
    if piactl connect &>/dev/null; then
        echo "✓ Connect command sent"
        echo "  Waiting for connection (this may take 10-15 seconds)..."
        
        # Wait for connection with timeout
        MAX_WAIT=30
        WAIT_COUNT=0
        while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
            sleep 1
            STATE=$(piactl get connectionstate 2>&1)
            
            if [ "$STATE" = "Connected" ]; then
                echo "✓ VPN Connected!"
                VPN_IP=$(piactl get vpnip 2>&1)
                echo "  VPN IP: $VPN_IP"
                break
            elif [ "$STATE" = "Connecting" ]; then
                echo -n "."
            else
                echo "✗ Connection failed: $STATE"
                echo ""
                echo "Troubleshooting:"
                echo "  1. Check PIA daemon logs:"
                echo "     sudo tail -50 /opt/piavpn/var/daemon.log"
                echo ""
                echo "  2. Look for 'Bad argument REJECT' errors"
                echo ""
                echo "  3. Verify firewall rules:"
                echo "     sudo nft list ruleset | grep pia"
                exit 1
            fi
            
            WAIT_COUNT=$((WAIT_COUNT + 1))
        done
        
        if [ $WAIT_COUNT -eq $MAX_WAIT ]; then
            echo ""
            echo "⚠️  Connection timeout after ${MAX_WAIT}s"
            echo "Check daemon logs for details"
            exit 1
        fi
    else
        echo "✗ Connect command failed"
        exit 1
    fi
fi

echo ""
echo "Connection verification:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
piactl get connectionstate
piactl get vpnip
piactl get protocol 2>&1 || true
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "✅ Phase 5 Complete - VPN connection tested"
echo ""
echo "Next: Run Phase 6 to verify no leaks"
