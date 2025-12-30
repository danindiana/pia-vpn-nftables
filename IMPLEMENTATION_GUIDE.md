# PIA VPN v3.7.0 nftables Implementation Guide
## PEER-REVIEWED & CORRECTED VERSION

### Executive Summary

The original proposals are **technically sound** but contain several implementation
details that need correction. This guide provides the corrected, production-ready
implementation path.

---

## ✅ VALIDATED FINDINGS

1. **Root Cause Confirmed**: PIA v3.7.0's firewall module uses legacy iptables
   `REJECT` target syntax incompatible with iptables-nft wrapper
   
2. **UFW Conflict Confirmed**: UFW's nftables rules persist in kernel even when
   switching to iptables-legacy
   
3. **Multi-Interface Routing Risk Confirmed**: Weighted nexthop routes can
   interfere with VPN's split-tunnel routing

---

## ⚠️ CRITICAL CORRECTIONS

### Correction 1: PIA Configuration Method

**WRONG (from original proposal):**
```bash
sudo mkdir -p /etc/piavpn/custom
echo '{"bypassFirewall": true}' | sudo tee /etc/piavpn/custom/firewall.json
```

**CORRECT:**
```bash
# Use PIA's CLI - it's the officially supported method
piactl set killswitch off
piactl applysettings
```

The `firewall.json` approach is undocumented and may not work across all PIA versions.

### Correction 2: nftables Rule Priority

**ISSUE**: Original rules use `priority 0` which may conflict with existing rules.

**IMPROVED**:
```nft
chain output {
    type filter hook output priority filter; policy drop;
    #                           ^^^^^^ 
    # Use 'filter' keyword instead of numeric 0 for better compatibility
    jump allow-vpn
}
```

### Correction 3: PIA Server IP Detection

**WRONG**: Hardcoded IP ranges may become outdated

**CORRECT**: Dynamic detection using PIA's regions data
```bash
# Extract from PIA's regions.json (see nftables-pia-setup.sh)
jq -r '.regions[].servers.ovpn[].ip' /opt/piavpn/var/daemon/regions.json
```

### Correction 4: DNS Configuration Timing

**ISSUE**: Original proposal configures static DNS before VPN connects

**IMPROVED**: Let VPN push DNS, only use fallback if that fails
```bash
# In /etc/systemd/resolved.conf.d/pia-dns.conf
[Resolve]
# Don't set DNS= here - let VPN push it
FallbackDNS=1.1.1.1 8.8.8.8  # Only if VPN DNS fails
DNSSEC=no
```

---

## 📋 RECOMMENDED IMPLEMENTATION PATH

### Phase 0: Pre-Flight Checks (5 minutes)

Run the configuration validator:
```bash
chmod +x pia-config-validator.sh
sudo ./pia-config-validator.sh
```

**Expected output should show:**
- iptables version (confirm if using nftables)
- PIA settings (kill switch, LAN access)
- Config file locations

**Decision point:**
- If using iptables-legacy → PIA may work, try connecting first
- If using iptables-nft → Proceed with implementation

---

### Phase 1: Backup Everything (5 minutes)

**CRITICAL**: Create comprehensive backup before making changes

```bash
# 1. Backup firewall rules
sudo nft list ruleset > ~/pia-backup/nftables-$(date +%Y%m%d).nft
sudo iptables-save > ~/pia-backup/iptables-$(date +%Y%m%d).rules

# 2. Backup routing table
ip route show > ~/pia-backup/routes-$(date +%Y%m%d).txt

# 3. Backup network configuration
sudo cp -r /etc/ufw ~/pia-backup/ufw-backup/
sudo cp /etc/systemd/resolved.conf ~/pia-backup/ 2>/dev/null || true

# 4. Backup PIA settings
sudo cp -r /opt/piavpn/etc ~/pia-backup/pia-etc/ 2>/dev/null || true

echo "Backups saved to ~/pia-backup/"
ls -lh ~/pia-backup/
```

**Make emergency recovery script accessible:**
```bash
chmod +x emergency-recovery.sh
sudo cp emergency-recovery.sh /usr/local/bin/pia-emergency-recovery
echo "Emergency recovery: sudo /usr/local/bin/pia-emergency-recovery"
```

---

### Phase 2: Handle Multi-Interface Routing (10 minutes)

**Only if you have weighted nexthop routes**

Run the routing manager:
```bash
chmod +x multi-interface-routing.sh
sudo ./multi-interface-routing.sh
```

**Recommendation**: Choose Option 1 (simplify to single route)
- Easiest to configure
- Most reliable with VPN
- Can restore multi-interface later

**Why this matters:**
Your current setup has 3 default routes with different weights. This creates
ambiguity in routing decisions that interferes with VPN's split-tunnel routes.

---

### Phase 3: Configure PIA Without Built-in Firewall (2 minutes)

```bash
# Disable PIA's firewall module (it doesn't work with nftables)
piactl set killswitch off

# Allow LAN traffic (important for development)
piactl set allowlan true

# Apply settings
piactl applysettings

# Verify
piactl get killswitch  # Should show: off
piactl get allowlan    # Should show: true
```

---

### Phase 4: Install nftables Kill Switch (15 minutes)

**Use the enhanced setup script:**
```bash
chmod +x nftables-pia-setup.sh
sudo ./nftables-pia-setup.sh
```

**What this script does:**
1. Detects your physical network interfaces automatically
2. Discovers PIA server IPs dynamically
3. Detects your LAN subnet for local access
4. Generates custom nftables rules
5. Validates syntax before applying
6. Creates backup before making changes
7. Makes rules persistent

**You will be prompted to confirm** - review the generated rules before applying.

**Key features of these rules:**
- ✅ Kill switch: Blocks all non-VPN traffic when VPN disconnects
- ✅ LAN access: Maintains local network connectivity
- ✅ Dynamic PIA server detection: Works across regions
- ✅ Proper logging: Failed connections logged with "PIA-BLOCKED:" prefix

---

### Phase 5: Test Connection (5 minutes)

```bash
# Connect to VPN
piactl connect

# Wait for connection (usually 5-10 seconds)
sleep 10

# Check connection state
piactl get connectionstate  # Should show: Connected
piactl get vpnip            # Should show VPN IP
```

**If connection fails:**
```bash
# Check daemon logs for errors
sudo tail -30 /opt/piavpn/var/daemon.log

# Common issues:
# - "Bad argument REJECT" → firewall still interfering (check killswitch setting)
# - "DNS resolution failed" → see Phase 6
# - "Routing conflict" → check ip route show
```

---

### Phase 6: Verify No Leaks (10 minutes)

**Run comprehensive diagnostic:**
```bash
chmod +x pia-diagnostic.sh
sudo ./pia-diagnostic.sh
```

**Critical tests to pass:**
1. ✅ VPN connection state: Connected
2. ✅ Public IP matches VPN IP (no IP leak)
3. ✅ DNS resolution works
4. ✅ Kill switch blocks traffic when disconnected

**Manual leak tests:**
```bash
# Test 1: IP leak check
curl https://api.ipify.org  # Should show VPN IP, not your real IP

# Test 2: DNS leak check  
dig +short whoami.akamai.net  # Should route through VPN

# Test 3: Kill switch test
piactl disconnect
ping -c 1 1.1.1.1  # Should FAIL (timeout/blocked)
piactl connect     # Reconnect

# Test 4: WebRTC leak (use browser)
# Visit: https://browserleaks.com/webrtc
# Should only show VPN IP, not local IP
```

---

### Phase 7: Monitor Stability (24-48 hours)

**Set up monitoring:**
```bash
# Create simple watchdog
cat > /usr/local/bin/pia-watchdog.sh << 'EOF'
#!/bin/bash
VPN_IP=$(piactl get vpnip 2>/dev/null)
PUBLIC_IP=$(curl -s --max-time 3 https://api.ipify.org 2>/dev/null)

if [ "$VPN_IP" != "$PUBLIC_IP" ]; then
    logger "PIA LEAK DETECTED: VPN=$VPN_IP Public=$PUBLIC_IP"
    # Optional: auto-disconnect to enforce kill switch
    # piactl disconnect
fi
EOF

chmod +x /usr/local/bin/pia-watchdog.sh

# Add to crontab (every 5 minutes)
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/pia-watchdog.sh") | crontab -
```

**Check logs periodically:**
```bash
# System logs
journalctl -u piavpn.service --since "1 hour ago"

# PIA daemon log
sudo tail -50 /opt/piavpn/var/daemon.log

# Firewall blocks
sudo journalctl --since "1 hour ago" | grep "PIA-BLOCKED"
```

---

## 🔥 EMERGENCY PROCEDURES

### Quick Recovery (Network Down)

**If you lose all network connectivity:**
```bash
sudo /usr/local/bin/pia-emergency-recovery

# This will:
# 1. Stop PIA service
# 2. Remove tun0 interface
# 3. Flush firewall rules
# 4. Restore network manager
# 5. Test connectivity
# 6. Provide recovery log
```

### Restore Original Configuration

**To completely undo all changes:**
```bash
# 1. Stop PIA
sudo systemctl stop piavpn.service

# 2. Restore nftables
sudo nft flush ruleset
sudo nft -f ~/pia-backup/nftables-YYYYMMDD.nft

# 3. Restore routing (if you simplified it)
sudo /tmp/restore-multiif-routing.sh

# 4. Re-enable UFW (if you disabled it)
sudo ufw enable

# 5. Restore PIA settings
piactl set killswitch auto
piactl applysettings
```

---

## 📊 TROUBLESHOOTING DECISION TREE

```
VPN won't connect
├─ Check: piactl get connectionstate
│  ├─ "Connecting" stuck → Check daemon logs for errors
│  ├─ "Disconnected" → Check firewall rules blocking handshake
│  └─ "Unknown" → Restart piavpn.service
│
VPN connects but no internet
├─ Check: ip route show | grep tun0
│  ├─ No tun0 routes → VPN routing failed
│  ├─ tun0 exists but low priority → Check weighted nexthop
│  └─ Routes look good → Check nftables rules
│
DNS doesn't work
├─ Check: resolvectl status
│  ├─ Wrong DNS servers → Check resolved.conf.d/
│  ├─ Correct servers but queries fail → nftables blocking UDP:53
│  └─ No DNS servers shown → VPN DNS push failed
│
IP leak detected
├─ Check: nft list ruleset | grep pia-vpn
│  ├─ No pia-vpn table → Rules not loaded
│  ├─ Policy accept → Kill switch not enabled
│  └─ Rules exist → Check for gaps in coverage
```

---

## ✅ SUCCESS CRITERIA

**Your implementation is complete when:**

1. ✅ VPN connects without "Bad argument REJECT" errors
2. ✅ Public IP matches VPN IP (confirmed via curl)
3. ✅ DNS resolution works (dig google.com succeeds)
4. ✅ Kill switch prevents leaks (traffic blocked when VPN down)
5. ✅ LAN access maintained (can reach 192.168.1.x devices)
6. ✅ No errors in daemon log after 1 hour of use
7. ✅ Survives reboot (VPN auto-connects, rules persist)

---

## 🎯 KEY DIFFERENCES FROM ORIGINAL PROPOSALS

| Original Proposal | Corrected Version | Reason |
|------------------|-------------------|--------|
| Manual firewall.json edit | Use piactl CLI | Official method |
| Static PIA IP ranges | Dynamic detection | Future-proof |
| Priority 0 | Priority filter | Better compatibility |
| Static DNS config | Fallback DNS only | Let VPN push DNS |
| Immediate full deployment | Phased rollout | Risk mitigation |
| Basic recovery script | Comprehensive recovery | Edge case handling |

---

## 📝 ADDITIONAL INSIGHTS

### Why This Setup Works

**The key insight** is that PIA's firewall module tries to use iptables commands
that don't translate properly to nftables. By disabling PIA's firewall and
implementing native nftables rules, we bypass the translation layer entirely.

**The kill switch works** because nftables rules are evaluated in the kernel
before routing decisions, so even if the VPN drops, outgoing packets are
blocked before they can leak through physical interfaces.

### Alternative: Manual OpenVPN (Not Recommended for Most Users)

If Tier 1 fails, you could switch to manual OpenVPN configuration, but you'd lose:
- PIA's GUI server selection
- Automatic port forwarding
- Easy region switching
- Integrated kill switch UI

**Only use manual OpenVPN if:**
- You need absolute control over OpenVPN parameters
- You're automating VPN connections in scripts
- Tier 1 implementation completely fails

---

## 📚 REFERENCES & FURTHER READING

- PIA Linux Documentation: https://helpdesk.privateinternetaccess.com/guides/linux
- nftables Wiki: https://wiki.nftables.org
- iptables vs nftables: https://developers.redhat.com/blog/2020/08/18/iptables-the-two-variants-and-their-relationship-with-nftables
- VPN Kill Switches Explained: https://www.ivpn.net/knowledgebase/linux/linux-how-do-i-prevent-vpn-leaks-using-nftables-and-openvpn/

---

## 🔒 SECURITY NOTES

**This implementation provides:**
- ✅ Network-level kill switch (prevents application leaks)
- ✅ Defense in depth (nftables + routing)
- ✅ Leak protection (IP, DNS, WebRTC via firewall)

**This does NOT protect against:**
- ❌ Application-level leaks (apps that detect VPN and bypass)
- ❌ Browser fingerprinting
- ❌ Time-based correlation attacks

**For maximum privacy:**
- Use Tor Browser for sensitive browsing
- Disable WebRTC in browser settings
- Use DNS over HTTPS (DoH) as additional layer

---

## ⏱️ TOTAL ESTIMATED TIME

| Phase | Time | Complexity |
|-------|------|------------|
| Pre-flight checks | 5 min | Easy |
| Backup | 5 min | Easy |
| Routing config | 10 min | Medium |
| PIA config | 2 min | Easy |
| nftables setup | 15 min | Medium |
| Testing | 5 min | Easy |
| Verification | 10 min | Medium |
| **Total** | **~50 min** | **Medium** |

Plus 24-48 hours of monitoring before considering complete.

---

**END OF GUIDE**

Remember: Take backups seriously. The emergency recovery script is your safety net.

Questions or issues? Review the diagnostic output and daemon logs first.
