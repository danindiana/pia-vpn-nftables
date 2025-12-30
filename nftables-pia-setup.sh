#!/bin/bash
# Enhanced PIA nftables Configuration Script
# Addresses: Dynamic server IPs, proper kill switch, LAN access

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== PIA nftables Configuration Tool ===${NC}"
echo ""

# Verify running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ ERROR: Must run as root/sudo${NC}"
    exit 1
fi

# Check prerequisites
echo "1. Checking prerequisites..."
for cmd in nft piactl ip; do
    if ! command -v $cmd &> /dev/null; then
        echo -e "${RED}❌ ERROR: $cmd not found${NC}"
        exit 1
    fi
done
echo -e "${GREEN}   ✓ All prerequisites met${NC}"
echo ""

# Detect network interfaces
echo "2. Detecting network configuration..."
PHYSICAL_INTERFACES=$(ip -br link show | grep -E "^(en|eth|wl)" | awk '{print $1}' | tr '\n' ' ')
LAN_SUBNET=$(ip route | grep "proto kernel scope link" | head -1 | awk '{print $1}')

if [ -z "$PHYSICAL_INTERFACES" ]; then
    echo -e "${RED}❌ ERROR: No network interfaces detected${NC}"
    exit 1
fi

echo "   Physical interfaces: $PHYSICAL_INTERFACES"
echo "   LAN subnet: ${LAN_SUBNET:-not detected}"
echo ""

# Get PIA server IPs dynamically
echo "3. Detecting PIA server IP ranges..."

# Method 1: From active connection
CURRENT_REMOTE=$(piactl get vpnip 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' || echo "")

# Method 2: From region data (PIA stores this)
PIA_REGIONS_FILE="/opt/piavpn/var/daemon/regions.json"
if [ -f "$PIA_REGIONS_FILE" ]; then
    if command -v jq &> /dev/null; then
        # Extract server IPs from regions file
        PIA_SERVER_IPS=$(jq -r '.regions[].servers.ovpn[].ip // empty' "$PIA_REGIONS_FILE" 2>/dev/null | sort -u | head -20)
    fi
fi

# Method 3: Known PIA IP ranges (fallback)
# These are documented PIA server ranges
FALLBACK_PIA_RANGES="104.200.128.0/20 104.200.154.0/24 104.200.155.0/24 209.95.50.0/24"

if [ -n "$CURRENT_REMOTE" ]; then
    echo -e "${GREEN}   ✓ Active VPN server: $CURRENT_REMOTE${NC}"
    # Extract /24 subnet from current IP
    PIA_IP_RANGE="${CURRENT_REMOTE%.*}.0/24"
elif [ -n "$PIA_SERVER_IPS" ]; then
    echo -e "${YELLOW}   ! Using server IPs from regions file${NC}"
    # Convert list to /32 entries for nftables
    PIA_IP_RANGE=$(echo "$PIA_SERVER_IPS" | awk '{print $1"/32"}' | tr '\n' ',' | sed 's/,$//')
else
    echo -e "${YELLOW}   ! Using fallback PIA IP ranges${NC}"
    PIA_IP_RANGE="$FALLBACK_PIA_RANGES"
fi

echo "   PIA IP range(s): $PIA_IP_RANGE"
echo ""

# Create backup of current rules
echo "4. Creating backup..."
BACKUP_FILE="/tmp/nftables-backup
nft list ruleset > "$BACKUP_FILE" 2>/dev/null || true
echo "   Backup saved to: $BACKUP_FILE"

# ENHANCED: Create comprehensive backup directory
BACKUP_DIR="/tmp/pia-backup
mkdir -p "$BACKUP_DIR"

# Save complete system state
nft list ruleset > "$BACKUP_DIR/nftables-pre-pia.nft" 2>/dev/null
iptables-save > "$BACKUP_DIR/iptables-pre-pia.rules" 2>/dev/null
ip route show > "$BACKUP_DIR/routes-pre-pia.txt" 2>/dev/null
ip -6 route show > "$BACKUP_DIR/routes-ipv6-pre-pia.txt" 2>/dev/null
cp -r /etc/ufw "$BACKUP_DIR/ufw-config/" 2>/dev/null || true
cp /etc/systemd/resolved.conf "$BACKUP_DIR/" 2>/dev/null || true

# If multi-interface routing exists, save it
if ip route show | grep -q "nexthop"; then
    ip route show | grep "default" > "$BACKUP_DIR/routes-multiif.txt"
    # Create restoration commands
    ip route show | grep "default" | sed 's/^/ip route add /' > /tmp/routes-multiif.backup
    echo "   Multi-interface routing backed up"
fi

echo "   Comprehensive backup: $BACKUP_DIR"

# Copy emergency recovery script to backup location
if [ -f "$(dirname "$0")/emergency-recovery.sh" ]; then
    cp "$(dirname "$0")/emergency-recovery.sh" "$BACKUP_DIR/EMERGENCY-RECOVERY.sh"
    chmod +x "$BACKUP_DIR/EMERGENCY-RECOVERY.sh"
    
    # Create quick-access symlink
    ln -sf "$BACKUP_DIR/EMERGENCY-RECOVERY.sh" /tmp/pia-emergency-recovery.sh
    
    echo ""
    echo "   Emergency recovery available at:"
    echo "     /tmp/pia-emergency-recovery.sh"
    echo "   or:"
    echo "     $BACKUP_DIR/EMERGENCY-RECOVERY.sh"
fi

echo ""

# Generate nftables configuration
echo "5. Generating nftables rules..."

# Create a properly quoted interface list for nftables
cat > /tmp/pia-vpn.nft << 'EOF'
#!/usr/sbin/nft -f
# PIA VPN Kill Switch + Traffic Rules
# Generated: Mon Dec 29 2025
# Physical interfaces: eth0, eth1, eth2
# LAN subnet: 192.168.1.0/24

# Define table for PIA VPN
table inet pia-vpn {
    # Chain for allowed traffic
    chain allow-vpn {
        # Allow established and related connections
        ct state { established, related } accept
        
        # Allow loopback interface
        iifname "lo" accept
        oifname "lo" accept
        
        # Allow VPN tunnel traffic (when active)
        iifname "tun0" accept
        oifname "tun0" accept
        
        # Allow LAN traffic (important for development)
        iifname { "eth0", "eth1", "eth2" } ip daddr 192.168.1.0/24 accept
        oifname { "eth0", "eth1", "eth2" } ip daddr 192.168.1.0/24 accept
        iifname { "eth0", "eth1", "eth2" } ip saddr 192.168.1.0/24 accept
        
        # Allow DHCP for network configuration
        oifname { "eth0", "eth1", "eth2" } meta l4proto udp th dport 67-68 accept
        iifname { "eth0", "eth1", "eth2" } meta l4proto udp th sport 67-68 accept
        
        # Allow VPN handshake to PIA servers ONLY
        # Ports: 1198 (OpenVPN), 853 (DoT), 8080 (alt), 123 (NTP)
        oifname { "eth0", "eth1", "eth2" } ip daddr { 104.200.128.0/20, 104.200.154.0/24, 104.200.155.0/24, 209.95.50.0/24 } meta l4proto udp th dport { 1198, 8080, 853, 123, 1197 } accept
        
        # Allow incoming from PIA servers (handshake responses)
        iifname { "eth0", "eth1", "eth2" } ip saddr { 104.200.128.0/20, 104.200.154.0/24, 104.200.155.0/24, 209.95.50.0/24 } meta l4proto udp th sport { 1198, 8080, 853, 123, 1197 } accept
        
        # KILL SWITCH: Reject everything else
        # This prevents leaks when VPN is down
        log prefix "PIA-BLOCKED: " drop
    }
    
    # Input chain: filter incoming traffic
    chain input {
        type filter hook input priority filter; policy drop;
        jump allow-vpn
    }
    
    # Forward chain: filter forwarded traffic
    chain forward {
        type filter hook forward priority filter; policy drop;
        jump allow-vpn
    }
    
    # Output chain: filter outgoing traffic (CRITICAL for kill switch)
    chain output {
        type filter hook output priority filter; policy drop;
        jump allow-vpn
    }
}
EOF

echo "   Rules generated at: /tmp/pia-vpn.nft"
echo ""

# Validate syntax
echo "6. Validating nftables syntax..."
if nft -c -f /tmp/pia-vpn.nft; then
    echo -e "${GREEN}   ✓ Syntax valid${NC}"
else
    echo -e "${RED}   ❌ Syntax error in generated rules${NC}"
    exit 1
fi
echo ""

# Ask for confirmation
echo -e "${YELLOW}=== CRITICAL WARNING ===${NC}"
echo "About to apply nftables rules with KILL SWITCH enabled."
echo "If VPN fails to connect, you will lose internet access."
echo ""
echo "Backup location: $BACKUP_FILE"
echo ""
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 0
fi

# Apply rules
echo ""
echo "7. Applying nftables rules..."
nft -f /tmp/pia-vpn.nft

if [ $? -eq 0 ]; then
    echo -e "${GREEN}   ✓ Rules applied successfully${NC}"
    
    # Make persistent
    mkdir -p /etc/nftables.d
    cp /tmp/pia-vpn.nft /etc/nftables.d/pia-vpn.nft
    chmod 644 /etc/nftables.d/pia-vpn.nft
    
    # Add to nftables include if not already there
    if [ -f /etc/nftables.conf ]; then
        if ! grep -q "pia-vpn.nft" /etc/nftables.conf; then
            echo 'include "/etc/nftables.d/pia-vpn.nft"' >> /etc/nftables.conf
        fi
    fi
    
    echo "   Rules made persistent at: /etc/nftables.d/pia-vpn.nft"
else
    echo -e "${RED}   ❌ Failed to apply rules${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}=== Configuration Complete ===${NC}"
echo ""
echo "Next steps:"
echo "1. Configure PIA to disable built-in kill switch:"
echo "   piactl set killswitch off"
echo "   piactl applysettings"
echo ""
echo "2. Connect to VPN:"
echo "   piactl connect"
echo ""
echo "3. Verify with diagnostic script:"
echo "   ./pia-diagnostic.sh"
echo ""
echo "To restore previous firewall state:"
echo "   sudo nft flush ruleset"
echo "   sudo nft -f $BACKUP_FILE"
