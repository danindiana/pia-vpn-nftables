#!/bin/bash
# Emergency Recovery Script for PIA VPN
# Restores network connectivity when VPN/firewall configuration fails

set +e  # Don't exit on errors during recovery

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║      EMERGENCY NETWORK RECOVERY PROCEDURE        ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "This script will attempt to restore network connectivity"
echo "by removing VPN configurations and resetting firewall rules."
echo ""

# Create recovery log
RECOVERY_LOG="/tmp/pia-recovery-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$RECOVERY_LOG") 2>&1

echo "Recovery started at: $(date)"
echo "Log file: $RECOVERY_LOG"
echo ""

# ENHANCED: Add cleanup trap for interruption
trap cleanup INT TERM EXIT

cleanup() {
    local EXIT_CODE=$?
    
    if [ $EXIT_CODE -ne 0 ] && [ $EXIT_CODE -ne 130 ]; then
        echo ""
        echo -e "${RED}━━━ Recovery Interrupted (exit code: $EXIT_CODE) ━━━${NC}"
        echo "Partial state may exist. Re-run script to complete recovery."
        if [ -n "$SNAPSHOT_DIR" ]; then
            echo "Pre-recovery snapshot: $SNAPSHOT_DIR"
        fi
    fi
    
    # Ensure log is finalized
    echo "Recovery ended at: $(date)" 2>/dev/null
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}ERROR: Must run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

# Step 1: Stop PIA service
echo "━━━ Step 1: Stopping PIA Service ━━━"
systemctl stop piavpn.service 2>/dev/null && echo "✓ PIA service stopped" || echo "! PIA service not running"
pkill -9 -f "pia-client" 2>/dev/null && echo "✓ Killed remaining PIA processes" || echo "! No PIA processes found"
pkill -9 -f "openvpn.*pia" 2>/dev/null && echo "✓ Killed OpenVPN processes" || echo "! No OpenVPN processes found"
sleep 1
echo ""

# Step 2: Remove VPN interface
echo "━━━ Step 2: Removing VPN Interface ━━━"
if ip link show tun0 &> /dev/null; then
    ip link set tun0 down 2>/dev/null
    ip link delete tun0 2>/dev/null && echo "✓ tun0 interface removed" || echo "! Failed to remove tun0"
else
    echo "✓ tun0 interface not present"
fi
echo ""

# Step 3: Flush firewall rules
echo "━━━ Step 3: Flushing Firewall Rules ━━━"

# Create pre-recovery snapshot
SNAPSHOT_DIR="/tmp/pre-recovery-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$SNAPSHOT_DIR"
nft list ruleset > "$SNAPSHOT_DIR/nftables-pre-recovery.nft" 2>/dev/null
iptables-save > "$SNAPSHOT_DIR/iptables-pre-recovery.rules" 2>/dev/null
ip route show > "$SNAPSHOT_DIR/routes-pre-recovery.txt" 2>/dev/null
echo "Pre-recovery snapshot: $SNAPSHOT_DIR"

# Detect which firewall system is active
if command -v nft &> /dev/null; then
    echo "Detected nftables..."
    
    # Try to restore from backup if exists
    LATEST_BACKUP=$(ls -t /tmp/nftables-backup/dev/null | head -1)
    if [ -n "$LATEST_BACKUP" ]; then
        echo "Found backup: $LATEST_BACKUP"
        
        # ENHANCED: Validate ruleset syntax before applying
        if nft -c -f "$LATEST_BACKUP" &>/dev/null; then
            echo "✓ Backup validation passed"
            read -p "Restore from backup? (yes/no): " RESTORE_BACKUP
            if [ "$RESTORE_BACKUP" = "yes" ]; then
                nft flush ruleset
                if nft -f "$LATEST_BACKUP"; then
                    echo "✓ Restored from backup"
                else
                    echo "! Restore failed, falling back to permissive rules"
                    nft flush ruleset
                    nft add table inet filter
                    nft add chain inet filter input '{ type filter hook input priority 0; policy accept; }'
                    nft add chain inet filter forward '{ type filter hook forward priority 0; policy accept; }'
                    nft add chain inet filter output '{ type filter hook output priority 0; policy accept; }'
                    echo "✓ Created fallback permissive ruleset"
                fi
            fi
        else
            echo "⚠ Backup file failed validation, creating permissive ruleset"
            nft flush ruleset
            nft add table inet filter
            nft add chain inet filter input '{ type filter hook input priority 0; policy accept; }'
            nft add chain inet filter forward '{ type filter hook forward priority 0; policy accept; }'
            nft add chain inet filter output '{ type filter hook output priority 0; policy accept; }'
            echo "✓ Created permissive nftables rules"
        fi
    else
        echo "No backup found, creating permissive ruleset..."
        
        # Create minimal permissive ruleset
        nft flush ruleset
        nft add table inet filter
        nft add chain inet filter input '{ type filter hook input priority 0; policy accept; }'
        nft add chain inet filter forward '{ type filter hook forward priority 0; policy accept; }'
        nft add chain inet filter output '{ type filter hook output priority 0; policy accept; }'
        echo "✓ Created permissive nftables rules"
    fi
fi

# Also handle iptables (might be hybrid state)
if command -v iptables &> /dev/null; then
    echo "Flushing iptables rules..."
    iptables -F 2>/dev/null && echo "✓ Flushed iptables filter table"
    iptables -t nat -F 2>/dev/null && echo "✓ Flushed iptables NAT table"
    iptables -t mangle -F 2>/dev/null && echo "✓ Flushed iptables mangle table"
    iptables -X 2>/dev/null && echo "✓ Deleted iptables custom chains"
    
    # Set permissive policies
    iptables -P INPUT ACCEPT 2>/dev/null
    iptables -P FORWARD ACCEPT 2>/dev/null
    iptables -P OUTPUT ACCEPT 2>/dev/null
    echo "✓ Set iptables to ACCEPT policy"
fi
echo ""

# Step 4: Restore/Reset UFW
echo "━━━ Step 4: UFW Management ━━━"
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    echo "UFW status: $UFW_STATUS"
    
    if echo "$UFW_STATUS" | grep -q "inactive"; then
        echo "✓ UFW already inactive"
    else
        read -p "Enable UFW (recommended for basic security)? (yes/no): " ENABLE_UFW
        if [ "$ENABLE_UFW" = "yes" ]; then
            ufw --force enable && echo "✓ UFW enabled" || echo "! UFW enable failed"
        else
            ufw --force disable && echo "✓ UFW disabled" || echo "! UFW disable failed"
        fi
    fi
else
    echo "! UFW not installed"
fi
echo ""

# Step 5: Detect and restore routing
echo "━━━ Step 5: Routing Table Recovery ━━━"

# Detect network manager
if systemctl is-active --quiet NetworkManager; then
    NETWORK_MANAGER="NetworkManager"
elif systemctl is-active --quiet systemd-networkd; then
    NETWORK_MANAGER="systemd-networkd"
else
    NETWORK_MANAGER="unknown"
fi

echo "Network manager: $NETWORK_MANAGER"

# Flush routing tables
echo "Flushing routing tables..."
ip route flush table main 2>/dev/null || true
ip route flush cache 2>/dev/null || true

# Detect gateway
GATEWAY=$(ip route show default 2>/dev/null | grep -oE 'via [0-9.]+' | head -1 | awk '{print $2}')
PRIMARY_IF=$(ip route show default 2>/dev/null | grep -oE 'dev [a-z0-9]+' | head -1 | awk '{print $2}')

echo "Detected gateway: ${GATEWAY:-none}"
echo "Detected primary interface: ${PRIMARY_IF:-none}"

# Restart network manager to restore routes
echo "Restarting network manager..."
case $NETWORK_MANAGER in
    NetworkManager)
        systemctl restart NetworkManager && echo "✓ NetworkManager restarted" || echo "! Restart failed"
        ;;
    systemd-networkd)
        systemctl restart systemd-networkd && echo "✓ systemd-networkd restarted" || echo "! Restart failed"
        ;;
    *)
        echo "! Unknown network manager, attempting manual route restoration"
        
        # Manual restoration if gateway detected
        if [ -n "$GATEWAY" ] && [ -n "$PRIMARY_IF" ]; then
            ip route add default via "$GATEWAY" dev "$PRIMARY_IF" && \
                echo "✓ Default route added manually" || \
                echo "! Failed to add default route"
        fi
        ;;
esac

sleep 2

# ENHANCED: Check for multi-interface configuration
echo "Checking for multi-interface configuration..."
INTERFACES=($(ip -br link show | grep -E "^(enp|eth)" | awk '{print $1}' | grep -v "@"))

if [ "${#INTERFACES[@]}" -gt 1 ] && [ -n "$GATEWAY" ]; then
    echo "Found ${#INTERFACES[@]} interfaces with gateway: $GATEWAY"
    
    # Check if backup routing config exists
    if [ -f /tmp/routes-multiif.backup ]; then
        echo "Restoring multi-interface routes from backup..."
        while IFS= read -r route_cmd; do
            eval "$route_cmd" 2>/dev/null && echo "  ✓ Restored route"
        done < /tmp/routes-multiif.backup
    else
        echo "! No multi-interface backup found"
        echo ""
        echo "If you had custom weighted routes, restore manually with:"
        echo "  sudo ip route add default \\"
        for i in "${!INTERFACES[@]}"; do
            weight=$((3 - i))
            if [ $weight -gt 0 ]; then
                echo "    nexthop via $GATEWAY dev ${INTERFACES[$i]} weight $weight \\"
            fi
        done | sed '$ s/ \\$//'
    fi
fi
echo ""

# Step 6: Reset DNS
echo "━━━ Step 6: DNS Recovery ━━━"

# Remove PIA DNS overrides
if [ -f /etc/systemd/resolved.conf.d/pia-dns.conf ]; then
    rm /etc/systemd/resolved.conf.d/pia-dns.conf && echo "✓ Removed PIA DNS override"
fi

# ENHANCED: Detect DNS management system
if systemctl is-active --quiet systemd-resolved; then
    echo "Detected: systemd-resolved"
    systemctl restart systemd-resolved && echo "✓ systemd-resolved restarted"
    
    # Verify DNS servers restored
    sleep 1
    CURRENT_DNS=$(resolvectl status 2>/dev/null | grep "DNS Servers" | head -1 || \
                  systemd-resolve --status 2>/dev/null | grep "DNS Servers" | head -1)
    if [ -n "$CURRENT_DNS" ]; then
        echo "Current DNS: $CURRENT_DNS"
    fi
    
elif systemctl is-active --quiet NetworkManager; then
    echo "Detected: NetworkManager DNS management"
    nmcli connection reload && echo "✓ NetworkManager configuration reloaded"
    
    # Force DNS refresh by cycling primary connection
    ACTIVE_CONN=$(nmcli -t -f NAME connection show --active | head -1)
    if [ -n "$ACTIVE_CONN" ]; then
        echo "Refreshing connection: $ACTIVE_CONN"
        nmcli connection down "$ACTIVE_CONN" 2>/dev/null || true
        sleep 1
        nmcli connection up "$ACTIVE_CONN" 2>/dev/null && echo "✓ Connection DNS refreshed"
    fi
    
elif [ -f /etc/resolv.conf ]; then
    if [ -L /etc/resolv.conf ]; then
        echo "✓ /etc/resolv.conf is managed (symlink)"
        TARGET=$(readlink -f /etc/resolv.conf)
        echo "  Points to: $TARGET"
    else
        echo "! /etc/resolv.conf is static"
        echo ""
        echo "Current nameservers:"
        grep "^nameserver" /etc/resolv.conf 2>/dev/null || echo "  None configured"
        echo ""
        echo "If DNS isn't working, add to /etc/resolv.conf:"
        echo "  nameserver 1.1.1.1"
        echo "  nameserver 8.8.8.8"
    fi
fi
echo ""

# Step 7: Verify connectivity
echo "━━━ Step 7: Connectivity Verification ━━━"
echo "Testing network connectivity..."

# Wait a moment for network to stabilize
sleep 2

# Test ping
echo -n "Ping test (1.1.1.1): "
if ping -c 1 -W 5 1.1.1.1 &>/dev/null; then
    echo -e "${GREEN}SUCCESS${NC}"
    PING_OK=true
else
    echo -e "${RED}FAILED${NC}"
    PING_OK=false
    
    # ENHANCED: Provide diagnostic context
    echo "  → Diagnostic: Checking routing..."
    DEFAULT_ROUTE=$(ip route show default 2>/dev/null | head -1)
    if [ -z "$DEFAULT_ROUTE" ]; then
        echo "    ✗ No default route found"
        echo "    Action: Run 'sudo ip route add default via <gateway> dev <interface>'"
    else
        echo "    ✓ Default route exists: $DEFAULT_ROUTE"
        echo "    → Testing gateway reachability..."
        
        # Test if gateway is reachable
        GATEWAY=$(echo "$DEFAULT_ROUTE" | grep -oE 'via [0-9.]+' | awk '{print $2}')
        if [ -n "$GATEWAY" ]; then
            echo -n "      Gateway ($GATEWAY): "
            if ping -c 1 -W 2 "$GATEWAY" &>/dev/null; then
                echo "reachable"
                echo "    ✗ Gateway works but external traffic blocked (likely firewall)"
            else
                echo "unreachable"
                echo "    ✗ Check physical network connection"
            fi
        fi
    fi
fi

# Test DNS
echo -n "DNS test (google.com): "
if command -v host &> /dev/null; then
    if host -W 5 google.com &>/dev/null; then
        echo -e "${GREEN}SUCCESS${NC}"
        DNS_OK=true
    else
        echo -e "${RED}FAILED${NC}"
        DNS_OK=false
        
        # ENHANCED: Diagnostic context
        echo "  → Diagnostic: Checking DNS configuration..."
        if [ -f /etc/resolv.conf ]; then
            NAMESERVERS=$(grep "^nameserver" /etc/resolv.conf | wc -l)
            if [ "$NAMESERVERS" -eq 0 ]; then
                echo "    ✗ No nameservers in /etc/resolv.conf"
                echo "    Action: Add 'nameserver 1.1.1.1' to /etc/resolv.conf"
            else
                echo "    ✓ Found $NAMESERVERS nameserver(s)"
                grep "^nameserver" /etc/resolv.conf | head -2
                echo "    → Testing direct DNS query..."
                if dig +short +time=2 google.com @1.1.1.1 &>/dev/null; then
                    echo "    ✓ Direct query to 1.1.1.1 works"
                    echo "    ✗ Issue with system DNS resolution (check systemd-resolved)"
                else
                    echo "    ✗ Cannot reach external DNS (firewall or routing issue)"
                fi
            fi
        fi
    fi
else
    echo "host command not available"
    DNS_OK=false
fi

# Test HTTPS
echo -n "HTTPS test: "
if curl -s --connect-timeout 5 -o /dev/null https://www.google.com 2>/dev/null; then
    echo -e "${GREEN}SUCCESS${NC}"
    HTTPS_OK=true
else
    echo -e "${RED}FAILED${NC}"
    HTTPS_OK=false
    
    # ENHANCED: Diagnostic context
    if [ "$PING_OK" = true ] && [ "$DNS_OK" = true ]; then
        echo "  → Ping and DNS work but HTTPS fails"
        echo "    Likely cause: Firewall blocking port 443"
        echo "    Check: sudo nft list ruleset | grep -i drop"
    elif [ "$PING_OK" = true ]; then
        echo "  → Basic connectivity exists but DNS/HTTPS fail"
        echo "    Likely cause: DNS resolution issue"
    else
        echo "  → No network connectivity at all"
        echo "    Check: Physical connection, default route, firewall"
    fi
fi
echo ""

# Step 8: Summary and recommendations
echo "━━━ Recovery Summary ━━━"
echo ""

if [ "$PING_OK" = true ] && [ "$DNS_OK" = true ] && [ "$HTTPS_OK" = true ]; then
    echo -e "${GREEN}✓ RECOVERY SUCCESSFUL${NC}"
    echo "Network connectivity has been restored."
    echo ""
    echo "Next steps:"
    echo "  1. Review this log: $RECOVERY_LOG"
    echo "  2. Reconfigure PIA VPN using corrected settings"
    echo "  3. Run diagnostic script: ./pia-diagnostic.sh"
else
    echo -e "${YELLOW}⚠ PARTIAL RECOVERY${NC}"
    echo "Some connectivity issues remain."
    echo ""
    echo "Failed tests:"
    [ "$PING_OK" = false ] && echo "  - Ping (check routing and firewall)"
    [ "$DNS_OK" = false ] && echo "  - DNS (check /etc/resolv.conf and systemd-resolved)"
    [ "$HTTPS_OK" = false ] && echo "  - HTTPS (check internet connection)"
    echo ""
    echo "Manual troubleshooting needed:"
    echo "  1. Check: ip route show"
    echo "  2. Check: nft list ruleset (or iptables -L)"
    echo "  3. Check: systemctl status $NETWORK_MANAGER"
    echo "  4. Check: cat /etc/resolv.conf"
    echo ""
    echo "If still having issues, try:"
    echo "  sudo systemctl restart $NETWORK_MANAGER"
    echo "  sudo reboot"
fi

echo ""
echo "Recovery log saved to: $RECOVERY_LOG"
echo ""

# Optional: Restore multi-interface routing
echo "━━━ Optional: Multi-Interface Routing ━━━"
echo "If you had custom multi-interface routing (weighted nexthop), "
echo "you may need to restore it manually."
echo ""
echo "Example (adjust to your setup):"
echo "  ip route add default nexthop via 192.168.1.1 dev eth1 weight 3 \\"
echo "                        nexthop via 192.168.1.1 dev eth2 weight 2"
echo ""

read -p "Would you like to see your current routing table? (yes/no): " SHOW_ROUTES
if [ "$SHOW_ROUTES" = "yes" ]; then
    echo ""
    ip route show
fi

echo ""
echo -e "${GREEN}Recovery procedure complete.${NC}"
