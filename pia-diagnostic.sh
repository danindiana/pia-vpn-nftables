#!/bin/bash
# Comprehensive PIA VPN Diagnostic Tool
# Tests: Connectivity, DNS leaks, IP leaks, kill switch, routing

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}╔════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║     PIA VPN Comprehensive Diagnostic Report       ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
echo ""
echo "Date: $(date)"
echo "Hostname: $(hostname)"
echo ""

# Helper functions
print_header() {
    echo -e "${BLUE}━━━ $1 ━━━${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Test 1: Firewall Backend Detection
print_header "1. Firewall Backend Configuration"
IPTABLES_VERSION=$(iptables --version 2>&1)
echo "iptables version: $IPTABLES_VERSION"

if echo "$IPTABLES_VERSION" | grep -q "nf_tables"; then
    print_warning "Using iptables-nft (may cause PIA compatibility issues)"
    USING_NFTABLES=true
else
    print_success "Using iptables-legacy"
    USING_NFTABLES=false
fi

# Check alternatives
IPTABLES_ALT=$(update-alternatives --display iptables 2>/dev/null | grep "currently points" || echo "N/A")
echo "Alternative: $IPTABLES_ALT"
echo ""

# Test 2: UFW Status
print_header "2. UFW Status"
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status 2>/dev/null | head -1)
    echo "$UFW_STATUS"
    if echo "$UFW_STATUS" | grep -q "active"; then
        print_warning "UFW is active - may conflict with PIA firewall"
    else
        print_success "UFW is inactive"
    fi
else
    echo "UFW not installed"
fi
echo ""

# Test 3: PIA Service State
print_header "3. PIA Service Status"
if systemctl is-active --quiet piavpn.service; then
    print_success "PIA service is running"
    echo "Service status: $(systemctl is-active piavpn.service)"
    echo "Service enabled: $(systemctl is-enabled piavpn.service 2>/dev/null || echo 'unknown')"
else
    print_error "PIA service is NOT running"
    echo "Try: sudo systemctl start piavpn.service"
fi
echo ""

# Test 4: Network Interfaces
print_header "4. Network Interfaces"
ip -br link show | grep -E "UP|UNKNOWN" | while read -r line; do
    echo "$line"
done

if ip link show tun0 &> /dev/null; then
    print_success "VPN tunnel interface (tun0) exists"
    TUN0_EXISTS=true
else
    print_error "VPN tunnel interface (tun0) NOT found"
    TUN0_EXISTS=false
fi
echo ""

# Test 5: PIA Connection State
print_header "5. PIA Connection State"
if command -v piactl &> /dev/null; then
    CONN_STATE=$(piactl get connectionstate 2>/dev/null || echo "unknown")
    echo "Connection state: $CONN_STATE"
    
    if [ "$CONN_STATE" = "Connected" ]; then
        print_success "VPN is connected"
        
        VPN_IP=$(piactl get vpnip 2>/dev/null || echo "unknown")
        REGION=$(piactl get region 2>/dev/null || echo "unknown")
        
        echo "VPN IP: $VPN_IP"
        echo "Region: $REGION"
    else
        print_warning "VPN is NOT connected (State: $CONN_STATE)"
    fi
else
    print_error "piactl command not found"
fi
echo ""

# Test 6: Routing Table
print_header "6. Routing Table (VPN-relevant routes)"
echo "Default routes:"
ip route show | grep "default" | head -5

if [ "$TUN0_EXISTS" = true ]; then
    echo ""
    echo "tun0 routes:"
    ip route show | grep "tun0" | head -5
    
    # Check for split-tunnel routes
    if ip route show | grep -q "0.0.0.0/1\|128.0.0.0/1"; then
        print_success "VPN split-tunnel routes detected"
    else
        print_warning "VPN routes may not be properly configured"
    fi
fi
echo ""

# Test 7: DNS Configuration
print_header "7. DNS Configuration"
if command -v systemd-resolve &> /dev/null; then
    echo "systemd-resolved status:"
    systemd-resolve --status 2>/dev/null | grep -A 3 "DNS Servers" | head -8 || \
        resolvectl status 2>/dev/null | grep -A 3 "DNS Servers" | head -8
else
    echo "/etc/resolv.conf:"
    cat /etc/resolv.conf | grep -E "nameserver|search"
fi
echo ""

# Test 8: Firewall Rules (nftables)
print_header "8. Active Firewall Rules"
if [ "$USING_NFTABLES" = true ]; then
    echo "nftables rules (PIA-related):"
    nft list ruleset 2>/dev/null | grep -A 5 "pia-vpn\|pia-killswitch" || echo "No PIA nftables rules found"
else
    echo "iptables rules (PIA chains):"
    iptables -L -n -v 2>/dev/null | grep -A 3 "piavpn" || echo "No PIA iptables rules found"
fi
echo ""

# Test 9: Basic Connectivity
print_header "9. Connectivity Tests"

# Test internet connectivity
echo -n "Internet connectivity (ping 1.1.1.1): "
if ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
    print_success "OK"
else
    print_error "FAILED"
fi

# Test DNS resolution
echo -n "DNS resolution (dig google.com): "
if command -v dig &> /dev/null; then
    if dig +short +time=2 google.com @1.1.1.1 &>/dev/null; then
        print_success "OK"
    else
        print_error "FAILED"
    fi
else
    echo "dig not installed, trying host..."
    if host -W 2 google.com &>/dev/null; then
        print_success "OK"
    else
        print_error "FAILED"
    fi
fi

# Test HTTPS connectivity
echo -n "HTTPS connectivity (curl): "
if curl -s --connect-timeout 3 -o /dev/null https://www.google.com 2>/dev/null; then
    print_success "OK"
else
    print_error "FAILED"
fi
echo ""

# Test 10: IP Leak Detection
print_header "10. IP Leak Detection"
if [ "$CONN_STATE" = "Connected" ]; then
    echo "Checking public IP..."
    
    # Get public IP from multiple sources
    PUBLIC_IP=$(curl -s --connect-timeout 3 https://api.ipify.org 2>/dev/null)
    PUBLIC_IP_ALT=$(curl -s --connect-timeout 3 https://icanhazip.com 2>/dev/null)
    
    echo "Public IP (ipify): ${PUBLIC_IP:-timeout}"
    echo "Public IP (icanhazip): ${PUBLIC_IP_ALT:-timeout}"
    echo "Expected VPN IP: $VPN_IP"
    
    if [ "$PUBLIC_IP" = "$VPN_IP" ] || [ "$PUBLIC_IP_ALT" = "$VPN_IP" ]; then
        print_success "No IP leak detected - using VPN IP"
    else
        print_error "POSSIBLE IP LEAK - public IP doesn't match VPN IP!"
    fi
else
    print_warning "Skipping leak test - VPN not connected"
fi
echo ""

# Test 11: DNS Leak Detection
print_header "11. DNS Leak Detection"
if [ "$CONN_STATE" = "Connected" ]; then
    echo "Testing DNS servers used..."
    
    # Query with system resolver
    if command -v dig &> /dev/null; then
        DNS_RESULT=$(dig +short whoami.akamai.net 2>/dev/null | tail -1)
        echo "DNS query result: ${DNS_RESULT:-failed}"
        
        # Get expected DNS servers from PIA
        EXPECTED_DNS=$(piactl get dns 2>/dev/null || echo "unknown")
        echo "Expected PIA DNS: $EXPECTED_DNS"
        
        # More comprehensive DNS leak test (optional, requires internet)
        echo ""
        echo "Comprehensive DNS leak test (dnsleaktest.com):"
        DNS_LEAK_IPS=$(dig +short @1.1.1.1 whoami.akamai.net bash.ws whoami.ultradns.net 2>/dev/null | sort -u)
        
        if echo "$DNS_LEAK_IPS" | grep -q "$VPN_IP"; then
            print_success "DNS appears to be routed through VPN"
        else
            print_warning "DNS may be leaking - IPs: $DNS_LEAK_IPS"
        fi
    else
        print_warning "dig not available for DNS leak test"
    fi
else
    print_warning "Skipping DNS leak test - VPN not connected"
fi
echo ""

# Test 12: Kill Switch Test
print_header "12. Kill Switch Test"
echo "This test temporarily disconnects VPN to verify kill switch blocks traffic."
read -p "Run kill switch test? (yes/no): " RUN_KILLSWITCH_TEST

if [ "$RUN_KILLSWITCH_TEST" = "yes" ] && [ "$CONN_STATE" = "Connected" ]; then
    echo "Disconnecting VPN..."
    piactl disconnect
    sleep 2
    
    echo -n "Testing connectivity with VPN disconnected: "
    if ping -c 1 -W 2 1.1.1.1 &>/dev/null; then
        print_error "KILL SWITCH FAILED - Traffic is NOT blocked!"
    else
        print_success "Kill switch working - traffic blocked"
    fi
    
    # Reconnect
    echo "Reconnecting VPN..."
    piactl connect
    sleep 3
else
    print_warning "Kill switch test skipped"
fi
echo ""

# Test 13: PIA Daemon Logs
print_header "13. Recent PIA Daemon Logs (last 15 lines)"
if [ -f /opt/piavpn/var/daemon.log ]; then
    tail -n 15 /opt/piavpn/var/daemon.log | grep -E "warning|error|REJECT|connect|disconnect" --color=never || echo "No recent errors/warnings"
else
    echo "Daemon log not found at /opt/piavpn/var/daemon.log"
fi
echo ""

# Summary
print_header "DIAGNOSTIC SUMMARY"
echo ""

if [ "$CONN_STATE" = "Connected" ] && [ "$PUBLIC_IP" = "$VPN_IP" ]; then
    print_success "VPN is connected and working properly"
elif [ "$CONN_STATE" = "Connected" ] && [ "$PUBLIC_IP" != "$VPN_IP" ]; then
    print_error "VPN shows connected but IP LEAK detected!"
    echo "  Recommendation: Check firewall rules and routing table"
elif [ "$CONN_STATE" != "Connected" ]; then
    print_warning "VPN is not connected"
    echo "  Recommendation: Run 'piactl connect' and retry diagnostics"
fi

echo ""
echo "For issues, check:"
echo "  1. Firewall backend compatibility (nftables vs iptables)"
echo "  2. UFW conflicts (disable if using custom nftables rules)"
echo "  3. Routing table configuration"
echo "  4. DNS configuration"
echo ""
echo -e "${BLUE}╚════════════════════════════════════════════════════╝${NC}"
