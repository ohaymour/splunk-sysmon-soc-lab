# Setup-SysmonAndForwarder.ps1
# Automates the repeatable Windows-side configuration steps for this project.
# Run as Administrator on DC01 or FS01, AFTER Sysmon and the Splunk Universal
# Forwarder have already been installed (installer steps are interactive and
# not scripted here - see the main project README).
#
# Assumes:
#   - Sysmon64.exe and sysmonconfig-export.xml are already present in C:\Sysmon
#   - Splunk Universal Forwarder is already installed at its default path

# --- 1. Apply the SwiftOnSecurity Sysmon configuration ---
$sysmonPath = "C:\Sysmon\Sysmon64.exe"
$configPath = "C:\Sysmon\sysmonconfig-export.xml"

if (Test-Path $sysmonPath) {
    & $sysmonPath -accepteula -c $configPath
    Write-Host "Sysmon configuration applied."
} else {
    Write-Warning "Sysmon64.exe not found at $sysmonPath - install Sysmon first."
}

# --- 2. Write the Splunk forwarder inputs.conf ---
$inputsConfPath = "C:\Program Files\SplunkUniversalForwarder\etc\system\local\inputs.conf"

$inputsConfContent = @"
[WinEventLog://Security]
index = wineventlog
disabled = false

[WinEventLog://System]
index = wineventlog
disabled = false

[WinEventLog://Application]
index = wineventlog
disabled = false

[WinEventLog://Microsoft-Windows-Sysmon/Operational]
index = sysmon
disabled = false
"@

Set-Content -Path $inputsConfPath -Value $inputsConfContent -Force
Write-Host "inputs.conf written to $inputsConfPath"

# --- 3. Restart the forwarder so it picks up the new config ---
Restart-Service SplunkForwarder
Start-Sleep -Seconds 5

# --- 4. Verify everything is running ---
Write-Host "`n--- Verification ---"
Get-Service Sysmon64
Get-Service SplunkForwarder
