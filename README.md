# Security Monitoring Lab: Splunk + Sysmon

## Objective

Extended the existing Stealthwork Active Directory lab with a centralized security monitoring layer — deployed a Splunk Enterprise indexer, forwarded Windows Event Logs and Sysmon telemetry from both domain-joined servers, and built detections mapped to the MITRE ATT&CK framework.

## Environment

- **Hypervisor:** VMware Workstation Pro
- **New host:** `SPLK01` — Ubuntu Server 26.04 LTS, 2 vCPU, 8GB RAM, 60GB disk
- **Network:** `VMnet2` (host-only, 192.168.10.0/24) — same lab network as the Stealthwork environment
- **Existing hosts (unchanged from Stealthwork):** `DC01` (192.168.10.10), `FS01` (192.168.10.20)
- **Splunk:** Splunk Enterprise (free license) on SPLK01, Splunk Universal Forwarder on DC01 and FS01
- **Endpoint telemetry:** Sysmon (SwiftOnSecurity configuration baseline) on DC01 and FS01

## Architecture

See [`/diagrams/network-topology.svg`](diagrams/network-topology.svg) for the network layout and [`/diagrams/data-flow-architecture.svg`](diagrams/data-flow-architecture.svg) for the full log pipeline, from endpoint event generation through to detections and the dashboard.

## Implementation

### Infrastructure

- Deployed SPLK01 as a dual-homed VM: one adapter on VMnet2 for lab connectivity (static IP `192.168.10.30`, configured via netplan — see [`/scripts/netplan-static-ip.yaml`](scripts/netplan-static-ip.yaml)), and a second NAT adapter for internet access needed to download Splunk and Sysmon.
- Took a clean VM snapshot (`ubuntu-26.04-clean-template`) before installing any Splunk-specific software, so the base OS image can be reused for future Linux-based projects.

### Splunk Enterprise (Indexer)

- Installed Splunk Enterprise on SPLK01 (see [`/scripts/splunk-indexer-setup.sh`](scripts/splunk-indexer-setup.sh) for the full command sequence, including a version-specific requirement to explicitly pass `--run-as-root`).
- Configured a receiving port on 9997 and created two indexes: `wineventlog` and `sysmon`.
- Extended the root filesystem to reclaim unused disk space discovered mid-project (see Troubleshooting below and [`/scripts/lvm-extend-disk.sh`](scripts/lvm-extend-disk.sh)).

### Endpoint Telemetry

- Installed Sysmon on both DC01 and FS01 using the industry-standard SwiftOnSecurity configuration.
- Installed the Splunk Universal Forwarder on both servers, configured to monitor the Security, System, and Application Windows Event Logs plus the Sysmon Operational log, and forward to SPLK01 on port 9997 (see [`/scripts/inputs.conf`](scripts/inputs.conf)).
- **Note:** DC01 and FS01 required different approaches — DC01 has its own internet access (for WSUS, from the original Stealthwork build) so downloads happened directly; FS01 has no internet access by design, so installer files were transferred in via RDP clipboard copy from the host machine.

### Detections and Dashboard

Built four detections, each mapped to a MITRE ATT&CK technique, saved as Splunk reports and surfaced on a "Security Monitoring Overview" dashboard. Full detail in [`/docs/Detections-and-MITRE-Mapping.md`](docs/Detections-and-MITRE-Mapping.md) and the raw SPL in [`/scripts/detections.spl`](scripts/detections.spl):

| Detection | MITRE ATT&CK |
|---|---|
| Repeated Failed Logons | T1110 — Brute Force |
| Privileged Group Change | T1098 — Account Manipulation |
| Suspicious PowerShell | T1059.001 — PowerShell |
| External RDP Logon | Ties to the Lab-RDP-Hardening GPO from Stealthwork |

## Challenges & Troubleshooting

Six real issues came up during this build — full detail on all of them in [`/docs/Troubleshooting-Log.md`](docs/Troubleshooting-Log.md). The most significant:

**1. Ambiguous virtual network configuration (occurred twice, independently)**

Both DC01 and FS01 were found to be misconfigured onto the wrong VMware virtual switch, despite having correct static IP addresses — VMware's plain "Host-only" setting turned out to be ambiguous on this system with multiple host-only networks defined. Diagnosed by isolating host-to-VM connectivity to determine which machine was actually unreachable, then resolved by explicitly selecting the specific virtual network (VMnet2) rather than relying on the default. This happening on two separate machines confirmed it as a systemic configuration issue worth checking on every VM going forward, not a one-off mistake.

**2. Splunk silently failing to start under root**

`splunk start` produced only a deprecation warning and exited without starting the service or any error message — this Splunk version requires the `--run-as-root` flag explicitly rather than just warning and continuing.

**3. Forwarding configured but not actually working**

Splunk Web showed the receiving port as "Enabled," but nothing was actually listening on it at the OS level (confirmed via `ss -tulnp`) until a full service restart was performed — the UI setting had saved without the running process actually opening the socket.

**4. Disk space threshold blocking all searches**

Splunk refused to run searches after free disk space dropped below its built-in 5GB safety margin. Investigating further revealed the VM's logical volume had never been extended to use the full disk — 19GB was sitting allocated but unused. Fixed at the root cause by extending the logical volume and filesystem, not just clearing temporary files.

## Lessons Learned

Most of the real learning in this project came from operational troubleshooting rather than the initial setup — reading Splunk's internal logs (`splunkd.log`), checking actual OS-level state (`ss`, `df`, `vgs`) rather than trusting a UI's displayed status, and recognizing when a problem (like the VMnet misconfiguration) was systemic rather than a one-time mistake. Working across Windows and Linux in the same project, and getting both to reliably forward data to a common indexer, was also a good forcing function for treating log correlation (timestamps, timezones) as something to verify explicitly rather than assume.

## Skills Demonstrated

Splunk Enterprise · Splunk Universal Forwarder · Sysmon · SIEM Administration · Linux System Administration (Ubuntu Server) · MITRE ATT&CK · Detection Engineering · Windows Event Log Analysis · VMware Workstation Networking · LVM Disk Management
