#!/bin/bash
# Multi-Interface Routing Manager for PIA VPN
# Safely handles weighted nexthop routes during VPN connections

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}=== Multi-Interface Routing Manager ===${NC}"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: Must run as root${NC}"
    exit 1
fi

# Function to display current routing
show_routing() {
    echo "Current routing table:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    ip route show | grep "default"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Function to backup current routes
backup_routes() {
    local backup_file="/tmp/routes-backup-$(date +%Y%m%d-%H%M%S).txt"
    ip route show > "$backup_file"
    echo -e "${GREEN}✓ Routing table backed up to: $backup_file${NC}"
    echo "$backup_file"
}

# Function to detect multi-interface setup
detect_multiif() {
    local default_count=$(ip route show | grep -c "default" || true)
    local nexthop_count=$(ip route show | grep -c "nexthop" || true)
    
    echo "Detected configuration:"
    echo "  - Default routes: $default_count"
    echo "  - Nexthop routes: $nexthop_count"
    echo ""
    
    if [ "$nexthop_count" -gt 0 ]; then
        return 0  # Multi-interface detected
    else
        return 1  # Single interface
    fi
}

# Main menu
echo "This script helps manage routing when using PIA VPN with multiple interfaces."
echo ""
show_routing

# Detect configuration
if detect_multiif; then
    echo -e "${YELLOW}⚠ Multi-interface routing detected${NC}"
    echo ""
    echo "Your current setup uses weighted nexthop routes. This can cause issues"
    echo "with VPN routing because the VPN's split-tunnel routes (0.0.0.0/1 and"
    echo "128.0.0.0/1) may not properly override all physical interface routes."
    echo ""
    echo "Options:"
    echo "  1) Simplify to single default route (recommended for VPN)"
    echo "  2) Keep multi-interface and add VPN-aware routing rules"
    echo "  3) Do nothing (may cause VPN routing issues)"
    echo "  4) View detailed routing explanation"
    echo ""
    read -p "Select option (1-4): " OPTION
    
    case $OPTION in
        1)
            # Simplify routing
            echo ""
            echo -e "${YELLOW}Simplifying routing configuration...${NC}"
            
            # Backup first
            BACKUP_FILE=$(backup_routes)
            echo ""
            
            # Detect interfaces and gateway
            GATEWAY=$(ip route show default | head -1 | grep -oE 'via [0-9.]+' | awk '{print $2}')
            INTERFACES=$(ip route show default | grep -oE 'dev [a-z0-9]+' | awk '{print $2}' | sort -u)
            
            echo "Detected gateway: $GATEWAY"
            echo "Detected interfaces: $INTERFACES"
            echo ""
            
            # Ask which interface to use as primary
            echo "Select primary interface for default route:"
            select PRIMARY_IF in $INTERFACES; do
                if [ -n "$PRIMARY_IF" ]; then
                    break
                fi
            done
            
            echo ""
            echo "Will configure: default via $GATEWAY dev $PRIMARY_IF"
            read -p "Proceed? (yes/no): " CONFIRM
            
            if [ "$CONFIRM" = "yes" ]; then
                # Remove all default routes
                echo "Removing existing default routes..."
                ip route show | grep "default" | while read -r route; do
                    ip route del $route 2>/dev/null || true
                done
                
                # Add single default route
                echo "Adding simplified default route..."
                ip route add default via "$GATEWAY" dev "$PRIMARY_IF" metric 100
                
                echo ""
                echo -e "${GREEN}✓ Routing simplified${NC}"
                echo ""
                show_routing
                
                # Create persistence script
                cat > /tmp/restore-multiif-routing.sh << EOF
#!/bin/bash
# Script to restore multi-interface routing
# Backup: $BACKUP_FILE

echo "Restoring multi-interface routing from backup..."
ip route flush table main
while read -r route; do
    ip route add \$route 2>/dev/null || echo "Failed: \$route"
done < "$BACKUP_FILE"

echo "Routing restored. Verify with: ip route show"
EOF
                chmod +x /tmp/restore-multiif-routing.sh
                
                echo "To restore your original multi-interface setup later:"
                echo "  sudo /tmp/restore-multiif-routing.sh"
                echo ""
                echo "Now connect VPN:"
                echo "  piactl connect"
            fi
            ;;
            
        2)
            # Advanced: VPN-aware routing rules
            echo ""
            echo -e "${BLUE}VPN-Aware Routing Rules${NC}"
            echo ""
            echo "This option uses routing policy database (RPDB) to handle"
            echo "VPN and multi-interface routing simultaneously."
            echo ""
            
            # Backup
            BACKUP_FILE=$(backup_routes)
            
            # Detect VPN interface
            if ip link show tun0 &> /dev/null; then
                echo "VPN interface tun0 detected"
                VPN_IF="tun0"
            else
                echo "VPN interface not detected. Connect VPN first and retry."
                exit 1
            fi
            
            # Get VPN routing table
            VPN_TABLE=100
            
            echo ""
            echo "Creating routing policy..."
            echo "  - VPN traffic: table $VPN_TABLE (tun0)"
            echo "  - Other traffic: main table (multi-interface)"
            echo ""
            
            # Create VPN routing table
            if ! grep -q "^$VPN_TABLE.*vpn" /etc/iproute2/rt_tables 2>/dev/null; then
                echo "$VPN_TABLE vpn" >> /etc/iproute2/rt_tables
            fi
            
            # Add VPN routes to separate table
            ip route add default dev tun0 table vpn
            
            # Add rule: mark VPN traffic
            ip rule add fwmark 0x1 table vpn priority 100
            
            echo -e "${GREEN}✓ VPN routing policy created${NC}"
            echo ""
            echo "You'll need to mark VPN traffic with fwmark 0x1 in nftables:"
            echo ""
            echo "Add to nftables rules:"
            echo "  meta mark set 0x1  # For VPN-destined packets"
            echo ""
            echo "This is an advanced configuration. Recommend using Option 1 instead."
            ;;
            
        3)
            echo ""
            echo "No changes made to routing configuration."
            echo ""
            echo -e "${YELLOW}WARNING:${NC} VPN may not work correctly with current routing."
            echo "If VPN connection fails, try Option 1."
            ;;
            
        4)
            # Educational content
            cat << 'EOF'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
              ROUTING EXPLANATION FOR VPN + MULTI-INTERFACE
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Your Current Setup (Multi-Interface):
───────────────────────────────────────
You have multiple default routes with weighted nexthop:

  default nexthop via 192.168.1.1 dev eth1 weight 3
  default nexthop via 192.168.1.1 dev eth2 weight 2
  default via 192.168.1.1 dev eth0 metric 100

This distributes traffic across multiple interfaces for load balancing
or redundancy.

Why VPN Has Issues:
──────────────────
When PIA connects, it adds routes like:

  0.0.0.0/1 dev tun0
  128.0.0.0/1 dev tun0

These should override the default routes (more specific /1 vs /0).
However, the kernel routing decision happens BEFORE nftables filtering.

The Problem Chain:
1. Packet arrives
2. Kernel selects route based on weighted nexthop (physical interface)
3. nftables sees packet going to physical interface
4. If nftables blocks non-VPN traffic, packet is dropped
5. Result: DNS fails, connections timeout

Solutions:
─────────
Option 1 (Simplest): Use single default route while VPN is active
  - Simple, reliable, works with standard VPN routing
  - Temporarily disables load balancing
  - Can restore multi-interface when VPN disconnects

Option 2 (Advanced): Use routing policy database (RPDB)
  - Maintains multi-interface for non-VPN traffic
  - VPN traffic goes to separate routing table
  - Requires advanced nftables packet marking
  - Complex to configure and maintain

Recommendation:
──────────────
Use Option 1 (simplify to single route) when VPN is active.
Your use case likely doesn't need multi-interface during VPN sessions.

EOF
            echo ""
            read -p "Press Enter to return to menu..."
            exec "$0"  # Restart script to show menu again
            ;;
            
        *)
            echo "Invalid option"
            exit 1
            ;;
    esac
else
    echo -e "${GREEN}✓ Single-interface routing detected${NC}"
    echo ""
    echo "Your routing configuration is already simplified and should"
    echo "work well with PIA VPN."
    echo ""
    echo "Current default route:"
    ip route show | grep "default"
    echo ""
    echo "This is compatible with VPN. No changes needed."
fi

echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
