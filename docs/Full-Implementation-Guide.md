# Security Monitoring Lab: Splunk + Sysmon — Full Implementation Guide

## 1. Objective

This project extends the existing Stealthwork Active Directory lab with a centralized security monitoring layer. A Splunk Enterprise indexer was deployed, Windows Event Logs and Sysmon telemetry were forwarded from both domain-joined servers, and four detections were built and mapped to the MITRE ATT&CK framework. The goal was to move from a well-secured but unmonitored environment (Stealthwork) to one where security-relevant activity is actually visible and searchable.

## 2. Environment

- **Hypervisor:** VMware Workstation Pro
- **New host:** `SPLK01` — Ubuntu Server 26.04 LTS, 2 vCPU, 8GB RAM, 40GB disk
- **Network:** `VMnet2` (host-only, 192.168.10.0/24) — the same lab network used by the Stealthwork environment
- **Existing hosts (unchanged from Stealthwork):** `DC01` (192.168.10.10, Domain Controller/DNS/WSUS/GPO), `FS01` (192.168.10.20, File Server)
- **Splunk:** Splunk Enterprise (free license, 500MB/day) on SPLK01, Splunk Universal Forwarder on DC01 and FS01
- **Endpoint telemetry:** Sysmon, configured with the SwiftOnSecurity baseline configuration

## 3. Architecture

The network topology (`/diagrams/network-topology.svg`) shows SPLK01 added to the existing lab network, including which hosts have internet access and which are intentionally isolated. The data flow diagram (`/diagrams/data-flow-architecture.svg`) shows the complete log pipeline: Windows Event Log and Sysmon telemetry generated on DC01/FS01, collected by the Splunk Universal Forwarder, sent over port 9997 to the SPLK01 indexer, split across two indexes, and surfaced through four detections and a dashboard.

A deliberate design decision carried over from Stealthwork: **DC01 has internet access (via a NAT adapter, originally for WSUS) and FS01 does not.** This project preserved that asymmetry rather than giving every machine internet access for convenience — FS01 holds the actual file shares and sensitive data, so minimizing its internet-facing surface is a reasonable security posture, even though it made the Sysmon/forwarder installation process on FS01 more involved (see Section 4.3).

## 4. Implementation

### 4.1 Infrastructure Provisioning

SPLK01 was created as a new VM with two network adapters: one connected to VMnet2 for lab connectivity, and a second NAT adapter purely for internet access needed to download Splunk and Sysmon installers. The VMnet2 adapter was assigned a static IP (`192.168.10.30`) via netplan, explicitly bound to the adapter's MAC address rather than relying on an interface name that could shift between boots (see `/scripts/netplan-static-ip.yaml`).

Before installing any Splunk-specific software, a clean VM snapshot (`ubuntu-26.04-clean-template`) was taken. This preserves a reusable base image — a fresh Ubuntu Server install with networking and system updates already applied — that can be cloned for future Linux-based projects on this same lab network rather than repeating the OS installation from scratch each time.

### 4.2 Splunk Enterprise Installation

Splunk Enterprise was installed on SPLK01 via the `.deb` package (see `/scripts/splunk-indexer-setup.sh` for the full command sequence). A receiving port was configured on 9997, and two indexes were created: `wineventlog` for standard Windows Event Log data, and `sysmon` for Sysmon telemetry specifically, keeping the two data types cleanly separated for search and detection purposes.

Partway through the build, Splunk's search functionality stopped working entirely due to a disk space threshold being reached. Investigating this surfaced a more fundamental issue — the VM's logical volume had never been extended to use its full allocated disk space, meaning roughly half of the provisioned storage was sitting unused. This was corrected by extending the logical volume and resizing the filesystem (see `/scripts/lvm-extend-disk.sh` and Section 5, Issue 4, for full detail).

### 4.3 Endpoint Telemetry (Sysmon)

Sysmon was installed on both DC01 and FS01 using the SwiftOnSecurity configuration — a widely used, community-maintained baseline that captures a broad set of security-relevant event types (process creation, network connections, and more) beyond what Windows logs by default.

The installation approach differed between the two hosts because of their different network access:

- **DC01** has its own internet access (inherited from the original Stealthwork WSUS configuration), so the Sysmon installer and configuration file were downloaded directly on the machine.
- **FS01** has no internet access by design. The same two files were downloaded on the host PC and transferred into FS01 via RDP clipboard copy-paste — a workaround that preserves FS01's isolation rather than temporarily opening it up to the internet just for convenience.

Both installations were verified via `Get-Service Sysmon64`, confirming the service running on each host.

### 4.4 Log Forwarding

The Splunk Universal Forwarder was installed on both DC01 and FS01, pointed at SPLK01's receiving port (9997). Each forwarder was configured with an identical `inputs.conf` (see `/scripts/inputs.conf`, applied via `/scripts/Setup-SysmonAndForwarder.ps1`), monitoring four channels: the Security, System, and Application Windows Event Logs, plus the Sysmon Operational log.

Ingestion was verified in Splunk Web by confirming both `index=wineventlog` and `index=sysmon` returned events tagged with `host=DC01` and `host=FS01`, with timestamps aligned to the actual current time (an explicit check, given that timezone misalignment between the Linux indexer and Windows endpoints could otherwise silently corrupt the usefulness of any time-based correlation).

### 4.5 Detections and Dashboard

Four detections were built as saved Splunk reports, each mapped to a specific MITRE ATT&CK technique, and combined into a single "Security Monitoring Overview" dashboard (four panels, one per detection). The raw SPL for each is in `/scripts/detections.spl`.

| Detection | Index | MITRE ATT&CK | Purpose |
|---|---|---|---|
| Repeated Failed Logons | `wineventlog` | T1110 — Brute Force | Flags any account/source-IP pair with more than 5 failed logon attempts (Event ID 4625), using a count threshold rather than alerting on every isolated failure. |
| Privileged Group Change | `wineventlog` | T1098 — Account Manipulation | Flags any addition to the `GRP_Admins` security group (Event IDs 4728/4732/4756) — scoped specifically to the identity model built in Stealthwork rather than a generic group-change alert. |
| Suspicious PowerShell | `sysmon` | T1059.001 — PowerShell | Flags PowerShell execution using common obfuscation/bypass flags (`-enc`, `-nop`) via Sysmon Event ID 1. |
| External RDP Logon | `wineventlog` | Ties to the Lab-RDP-Hardening GPO | Flags any RDP logon (Logon Type 10) originating from outside the lab subnet — a monitoring-side integrity check on the firewall-level RDP restriction already enforced by Stealthwork's GPO. |

**Status:** all four detections execute successfully against live, verified data (thousands of legitimate events confirmed flowing from both hosts), and all four currently return no results — which is the expected, correct state, since no brute-force attempts, privilege escalations, obfuscated PowerShell execution, or external RDP logons have actually occurred in the lab. A natural next step, noted but not yet built, would be to safely simulate one of these behaviors (e.g., a deliberate series of failed logons) to confirm each detection actually fires as designed.

## 5. Challenges and Troubleshooting

Six real issues occurred during this build — none staged. Each is documented here with the full diagnostic path, not just the fix, since the diagnostic process is the more transferable skill.

### Issue 1: DC01 Network Misconfiguration

**Symptom:** After configuring SPLK01's static IP, a ping from SPLK01 to DC01 failed with "Destination Host Unreachable."

**Diagnosis:** SPLK01's own network adapter setting was confirmed correct (explicitly set to VMnet2). DC01's setting, by contrast, was plain "Host-only" with no explicit network selected. Briefly switching DC01's setting to "Custom" to inspect it displayed "VMnet0" — this turned out to be a stale UI placeholder rather than DC01's actual connected network, an important distinction confirmed by not trusting that display value and instead running an isolation test from the host PC (which was independently confirmed to be on VMnet2): a ping to DC01 failed, while a ping to SPLK01 succeeded. This isolated the fault specifically to DC01.

**Root cause:** A network adapter's assigned IP address has no bearing on which virtual switch it is actually connected to. DC01's plain "Host-only" setting was resolving to a different virtual network than VMnet2, despite having a correctly configured `192.168.10.x` static IP.

**Fix:** DC01's network adapter was explicitly set to "Custom: Specific virtual network → VMnet2," followed by a full VM power-off and power-on — a live setting change alone was not sufficient to re-attach the virtual NIC to the new network.

**Verification:** Host-to-DC01 connectivity was confirmed first, followed by direct VM-to-VM connectivity from SPLK01 to DC01, since the latter is the actual requirement for log forwarding.

### Issue 2: FS01 Hit the Same Misconfiguration, Independently

**Symptom:** The same network issue as Issue 1 surfaced again on FS01 while preparing it for RDP access.

**Diagnosis and fix:** Identical to Issue 1 — plain "Host-only" corrected to an explicit VMnet2 selection.

**Significance:** This issue occurring independently on a second VM elevates it from an isolated mistake to a genuine, systemic characteristic of this particular VMware installation. The practical takeaway — always explicitly select a network by name on every new VM, never rely on the plain "Host-only" default — now applies to every future VM added to this lab.

### Issue 3: FS01's Remote Desktop Was Disabled Locally

**Symptom:** After resolving the network issue, RDP connections to FS01 still failed with "Remote access to the server is not enabled."

**Diagnosis:** Checked locally via the VMware console (since RDP could not be used to diagnose an RDP failure): Remote Desktop was toggled off in Windows Settings.

**Root cause:** The original Stealthwork build only ever used the VMware console to work on FS01, so Remote Desktop access had never been turned on.

**Fix:** Enabled Remote Desktop locally via System Settings, after which RDP connected successfully.

### Issue 4: Splunk Silently Failed to Start Under Root

**Symptom:** Running the standard Splunk start command produced only a deprecation warning about running as root, then returned to the shell prompt with no further output — no license prompt, no error, and no indication anything had failed.

**Diagnosis:** Running a status check immediately afterward re-triggered the same first-run initialization sequence, confirming Splunk had never actually completed startup on the previous attempt.

**Root cause:** This version of Splunk blocks starting as root unless an explicit override flag is provided, rather than warning and continuing as older versions did.

**Fix:** Adding the explicit `--run-as-root` flag allowed the full interactive license acceptance and administrator account setup to proceed, and Splunk started successfully. The same flag is required on any subsequent restart, not just the initial start.

**Note:** Splunk's own documentation recommends running the service under a dedicated non-root account rather than root at all. This is flagged here as a legitimate hardening step for a future iteration of this lab, not implemented in the current build.

### Issue 5: Forwarding Was "Configured" But Not Actually Working

**Symptom:** After installing the Universal Forwarder and configuring `inputs.conf` on both DC01 and FS01, the forwarder logs showed repeated connection failures to SPLK01's receiving port, explicitly stating the target machine was actively refusing the connection.

**Diagnosis:** The forwarder service itself was confirmed running, and Splunk on SPLK01 was confirmed running. Checking what was actually listening on the receiving port at the operating system level, however, showed nothing bound to it at all — despite Splunk Web's own configuration page showing the receiving port as enabled.

**Root cause:** The receiving-port setting had been saved at the application configuration level, but the running Splunk process had not actually opened the corresponding listening socket. A full service restart was required for the setting to take effect, rather than the toggle alone being sufficient.

**Fix:** A full Splunk restart (again requiring the `--run-as-root` flag) resulted in the port becoming genuinely bound, confirmed directly at the OS level rather than trusting the web interface's displayed status.

**Verification:** Restarting the forwarder service on both DC01 and FS01 afterward resulted in successful connections on both.

### Issue 6: Disk Space Threshold Blocked All Searches

**Symptom:** Attempting to run a search in Splunk Web returned an explicit error stating the minimum free disk space threshold had been reached, and the search would not execute.

**Diagnosis:** Checking disk usage confirmed free space had dropped to just above 4GB, under Splunk's built-in 5GB safety margin that exists specifically to prevent index corruption from running out of space mid-write. The most immediately reclaimable space was the several-gigabyte Splunk installer package still present in the home directory, along with the package manager's cache. After clearing both, free space rose enough to clear the immediate threshold, but remained tight. Examining the underlying disk allocation revealed a significant amount of space sitting unused within the volume group — the virtual disk had been provisioned at its intended size, but the root filesystem had only ever been allocated roughly half of it.

**Fix:** Beyond the immediate cleanup, the logical volume was extended to consume the remaining free space in the volume group, and the filesystem was resized to actually make use of the newly extended volume — addressing the root cause rather than only buying temporary headroom.

**Verification:** Confirmed via disk usage output showing the filesystem's total size roughly doubling, with comfortable free space remaining well clear of the threshold.

## 6. Lessons Learned

The majority of the genuine learning in this project came from operational troubleshooting rather than the initial setup steps. Several patterns worth carrying into future projects:

- **Don't trust a UI's displayed status over the actual system state.** Both the network adapter "Custom" dropdown and Splunk Web's receiving-port configuration appeared correct while the underlying reality was different — checking at the operating-system level (`ss`, direct connectivity tests) was what actually resolved both issues.
- **A problem that recurs on a second, independent system is systemic, not a one-off mistake.** The VMnet misconfiguration happening on both DC01 and FS01 turned a single troubleshooting incident into a documented pattern worth checking proactively on every future VM.
- **Cross-platform log correlation requires explicit verification, not assumption.** Getting a Linux indexer and Windows endpoints to agree on time was treated as something to actively confirm, not something that "should just work."
- **Root-cause fixes are worth the extra step over quick patches.** The disk space issue could have been "solved" by simply deleting files whenever space got tight again; extending the actual filesystem was a small amount of additional work that removes the problem permanently instead of deferring it.

## 7. Skills Demonstrated

Splunk Enterprise administration · Splunk Universal Forwarder deployment · Sysmon configuration · SIEM operations · Linux system administration (Ubuntu Server) · LVM disk management · MITRE ATT&CK-mapped detection engineering · Windows Event Log analysis · VMware Workstation networking and troubleshooting · Cross-platform log correlation

## Appendix: Repository Contents

- `/diagrams` — network topology and data flow architecture diagrams
- `/screenshots` — build evidence, organized to match this guide's sections
- `/scripts` — `netplan-static-ip.yaml`, `inputs.conf`, `splunk-indexer-setup.sh`, `lvm-extend-disk.sh`, `detections.spl`, `Setup-SysmonAndForwarder.ps1`
- `/docs/Full-Implementation-Guide.md` — this document
