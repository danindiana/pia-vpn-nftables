#!/bin/bash
# Phase 2: Multi-Interface Routing Analysis
# Checks if you have weighted routes that need simplification

echo "╔════════════════════════════════════════════════════╗"
echo "║  Phase 2: Multi-Interface Routing Analysis        ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

echo "Current routing configuration:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ip route show | head -20
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check for multi-interface setup
DEFAULT_COUNT=$(ip route show | grep -c "default" || true)
NEXTHOP_COUNT=$(ip route show | grep -c "nexthop" || true)

echo "Analysis:"
echo "  - Default routes: $DEFAULT_COUNT"
echo "  - Nexthop routes: $NEXTHOP_COUNT"
echo ""

if [ "$NEXTHOP_COUNT" -gt 0 ]; then
    echo "⚠️  Multi-interface routing detected (nexthop routes found)"
    echo ""
    echo "This setup can interfere with VPN routing. You have options:"
    echo ""
    echo "1) Run the interactive routing wizard:"
    echo "   sudo bash multi-interface-routing.sh"
    echo ""
    echo "2) Or manually simplify to single default route:"
    echo "   sudo ip route del <current weighted routes>"
    echo "   sudo ip route add default via <gateway> dev <interface>"
    echo ""
    echo "For now, proceeding with current routing configuration."
else
    echo "✅ No multi-interface weighting detected"
    echo "   Your routing is compatible with VPN"
fi

echo ""
echo "✅ Phase 2 Analysis Complete"
