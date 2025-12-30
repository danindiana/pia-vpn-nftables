# PIA VPN + nftables Kill Switch

A complete implementation for running PIA VPN with an nftables-based kill switch on Linux systems. This project solves the incompatibility between PIA v3.7.0+ and modern nftables firewalls by providing native firewall rules that work reliably.

## Problem Solved

PIA's built-in firewall (v3.7.0+) uses legacy iptables syntax that's incompatible with nftables-based systems. When attempting to connect, users see:
```
Bad argument REJECT: unknown reject type
```

This repository provides a working solution using native nftables rules.

## What's Included

### Phase Scripts (Copy & Execute)
- **PHASE1-backup.sh** - Comprehensive system backup before making changes
- **PHASE2-routing-check.sh** - Analyze your routing configuration
- **PHASE3-pia-config.sh** - Configure PIA CLI settings
- **PHASE4-nftables-install.sh** - Install and enable nftables kill switch
- **PHASE5-test-connection.sh** - Verify VPN connectivity
- **PHASE6-verify-leaks.sh** - Check for IP/DNS leaks

### Tool Scripts
- **nftables-pia-setup.sh** - Core nftables rule generator
- **pia-diagnostic.sh** - System analysis and troubleshooting
- **pia-config-validator.sh** - Pre-flight configuration check
- **emergency-recovery.sh** - One-command network recovery
- **multi-interface-routing.sh** - Advanced routing management

### Documentation
- **IMPLEMENTATION_GUIDE.md** - Technical implementation details
- **MASTER_EXECUTION_GUIDE.txt** - Step-by-step phase breakdown
- **QUICK_REFERENCE.txt** - Copy-paste commands
- **FINAL_REVIEW.md** - Production readiness notes
- **VALIDATION_SUMMARY.md** - Testing results

## Quick Start

### Prerequisites
```bash
# Install PIA CLI
curl -fsSL https://installer.pia.io/run | sh

# Install nftables
sudo apt install nftables  # Debian/Ubuntu
sudo dnf install nftables  # Fedora/RHEL

# Verify nftables is active
sudo systemctl status nftables
```

### Basic Setup
```bash
# 1. Backup your system
bash PHASE1-backup.sh

# 2. Check your routing
bash PHASE2-routing-check.sh

# 3. Configure PIA
bash PHASE3-pia-config.sh

# 4. Install firewall rules
sudo bash PHASE4-nftables-install.sh

# 5. Test the connection
bash PHASE5-test-connection.sh

# 6. Verify no leaks
bash PHASE6-verify-leaks.sh
```

## How It Works

The solution replaces PIA's broken firewall module with native nftables rules that:

1. **Allow VPN traffic** - Enables OpenVPN handshake on necessary ports (UDP 8080, 1198)
2. **Allow LAN access** - Keeps local network reachable (192.168.1.0/24)
3. **Allow DNS & DHCP** - Maintains network services
4. **Kill switch** - Blocks all non-VPN traffic with `drop` rules

### Generated Rules Location
```
/etc/nftables.d/pia-vpn.nft
```

Rules are applied on every boot via systemd and can be manually reloaded:
```bash
sudo nft -f /etc/nftables.d/pia-vpn.nft
```

## Emergency Recovery

If anything breaks, the emergency recovery script restores your previous configuration:
```bash
sudo bash emergency-recovery.sh
```

This restores:
- nftables configuration
- iptables rules
- Routing table
- DNS settings
- UFW status
- PIA configuration

## System Requirements

- **OS**: Linux (Debian, Ubuntu, Fedora, RHEL, etc.)
- **Firewall**: nftables or iptables-nft
- **VPN**: PIA CLI v3.7.0+
- **Kernel**: 4.19+ (for nftables)
- **Privileges**: Root access for firewall rules

## Troubleshooting

### Connection Issues
1. Check PIA status: `piactl get connectionstate`
2. Verify nftables rules: `sudo nft list ruleset`
3. Check OpenVPN logs: `sudo journalctl -u openvpn-pia -f`

### Rule Syntax Errors
Run the diagnostic tool:
```bash
sudo bash pia-diagnostic.sh
```

### Firewall Blocking Traffic
Review the kill switch rules to ensure your interface names match (eth0, eth1, etc.):
```bash
ip link show
```

## File Sanitization Note

This repository contains sanitized example configurations. Personal data has been replaced with generic placeholders:
- IP addresses → 203.0.113.1 (documentation example)
- Interface names → eth0, eth1, eth2
- Paths → /path/to/...
- Usernames → user@hostname

For production use, the scripts will auto-detect your actual system configuration.

## Key Features

✅ Works with nftables and iptables-nft  
✅ Multi-interface routing support  
✅ Persistent firewall rules  
✅ Emergency recovery built-in  
✅ Comprehensive diagnostics  
✅ LAN access maintained  
✅ DNS leak prevention  
✅ Automated Phase execution  

## Testing Verified

- ✅ VPN connects without firewall errors
- ✅ Kill switch blocks non-VPN traffic
- ✅ LAN subnet accessible (192.168.1.0/24)
- ✅ System survives VPN state transitions
- ✅ Emergency recovery functional

## License

This project is provided for educational and personal use.

## Support

For issues with:
- **PIA VPN**: https://www.privateinternetaccess.com
- **nftables**: Linux kernel documentation or your distro's nftables guide
- **This implementation**: Review FINAL_REVIEW.md or run pia-diagnostic.sh

---

**Version**: 2.0  
**Last Updated**: December 29, 2025  
**Tested on**: Linux with nftables/iptables-nft, PIA v3.7.0+
