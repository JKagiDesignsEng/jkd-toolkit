function Add-RunWindowsDefenderButton {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,300)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Run Windows Defender'
    $btn.Size = $Size
    $btn.Location = $Location

    $btn.Add_Click({
        try {
            # Prefer PowerShell Defender cmdlets when available
            if (Get-Command -Name Start-MpScan -ErrorAction SilentlyContinue) {
                Write-Host 'Starting Microsoft Defender quick scan using Start-MpScan (QuickScan)...'
                try {
                    Start-MpScan -ScanType QuickScan -ErrorAction Stop
                    Write-Host 'Defender scan invoked (Start-MpScan). Monitor Windows Security for progress/results.'
                } catch {
                    Write-Host "Start-MpScan failed: $($_.Exception.Message)"
                }
            } elseif (Test-Path "$env:ProgramFiles\Windows Defender\MpCmdRun.exe") {
                $mp = """$env:ProgramFiles\Windows Defender\MpCmdRun.exe"""
                Write-Host "Running: $mp -Scan -ScanType 1 (Quick scan)"
                try {
                    & $mp -Scan -ScanType 1
                } catch {
                    Write-Host "MpCmdRun invocation failed: $($_.Exception.Message)"
                }
            } else {
                Write-Host 'Microsoft Defender not available on this system (no Start-MpScan and MpCmdRun not found).'
            }
        } catch {
            Write-Host "Run Windows Defender button failed: $($_.Exception.Message)"
        } finally {
            # Preferred wrapper
            if (Get-Command -Name Invoke-WithDivider -ErrorAction SilentlyContinue) { Invoke-WithDivider -Action { } }
            else { if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider } }
        }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
