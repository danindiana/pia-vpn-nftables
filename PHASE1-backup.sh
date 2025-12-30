#!/bin/bash
# Phase 1: Comprehensive Backup Script
# Run this on your system: sudo bash PHASE1-backup.sh

set -e

echo "╔════════════════════════════════════════════════════╗"
echo "║  Phase 1: Comprehensive System Backup             ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""

BACKUP_DIR="$HOME/pia-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "Backup directory: $BACKUP_DIR"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "⚠️  WARNING: Not running as root. Some backups may fail."
    echo "Run as: sudo bash $0"
    echo ""
fi

# 1. Backup firewall rules
echo "━━━ Step 1: Firewall Rules ━━━"
nft list ruleset > "$BACKUP_DIR/nftables-$(date +%Y%m%d).nft" 2>/dev/null && \
    echo "✓ nftables rules backed up" || echo "✗ nftables backup failed"
    
iptables-save > "$BACKUP_DIR/iptables-$(date +%Y%m%d).rules" 2>/dev/null && \
    echo "✓ iptables rules backed up" || echo "✗ iptables backup failed"
echo ""

# 2. Backup routing table
echo "━━━ Step 2: Routing Table ━━━"
ip route show > "$BACKUP_DIR/routes-$(date +%Y%m%d).txt" && \
    echo "✓ Routes backed up" || echo "✗ Routes backup failed"
echo ""

# 3. Backup network configuration
echo "━━━ Step 3: Network Configuration ━━━"
cp /etc/systemd/resolved.conf "$BACKUP_DIR/" 2>/dev/null && \
    echo "✓ resolved.conf backed up" || echo "✗ resolved.conf backup failed"

if [ -d /etc/ufw ]; then
    cp -r /etc/ufw "$BACKUP_DIR/ufw-backup/" 2>/dev/null && \
        echo "✓ UFW config backed up" || echo "✗ UFW backup failed"
fi
echo ""

# 4. Backup PIA settings
echo "━━━ Step 4: PIA Settings ━━━"
if [ -d /opt/piavpn ]; then
    cp -r /opt/piavpn/etc "$BACKUP_DIR/pia-etc-backup/" 2>/dev/null && \
        echo "✓ PIA /etc backed up" || echo "✗ PIA /etc backup failed"
fi

if [ -d /opt/piavpn/var ]; then
    cp /opt/piavpn/var/daemon.log "$BACKUP_DIR/" 2>/dev/null && \
        echo "✓ PIA daemon.log backed up" || echo "✗ PIA daemon.log backup failed"
fi
echo ""

# 5. Make emergency recovery accessible
echo "━━━ Step 5: Emergency Recovery Setup ━━━"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [ -f "$SCRIPT_DIR/emergency-recovery.sh" ]; then
    cp "$SCRIPT_DIR/emergency-recovery.sh" /usr/local/bin/pia-emergency-recovery 2>/dev/null && \
        chmod +x /usr/local/bin/pia-emergency-recovery && \
        echo "✓ Emergency recovery installed to /usr/local/bin/pia-emergency-recovery" || \
        echo "✗ Emergency recovery setup failed (try: sudo cp emergency-recovery.sh /usr/local/bin/pia-emergency-recovery)"
fi
echo ""

# Summary
echo "╔════════════════════════════════════════════════════╗"
echo "║  Backup Complete                                   ║"
echo "╚════════════════════════════════════════════════════╝"
echo ""
echo "Backup location: $BACKUP_DIR"
echo ""
echo "Files backed up:"
ls -lh "$BACKUP_DIR"
echo ""
echo "To restore, save this location and use files from:"
echo "  - nftables rules: nftables-*.nft"
echo "  - iptables rules: iptables-*.rules"
echo "  - Routing: routes-*.txt"
echo "  - DNS config: resolved.conf"
echo ""
echo "✅ Phase 1 Complete - Ready for Phase 2"
