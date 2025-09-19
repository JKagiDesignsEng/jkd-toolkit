function Add-RunMMRButton {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,340)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
    )

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Run Microsoft Malicious Software Removal'
    $btn.Size = $Size
    $btn.Location = $Location

    $btn.Add_Click({
        try {
            # Typical location for mrt.exe
            $candidates = @(
                "$env:windir\system32\mrt.exe",
                "$env:windir\SysWOW64\mrt.exe"
            )
            $found = $null
            foreach ($p in $candidates) { if (Test-Path $p) { $found = $p; break } }
            if ($found) {
                Write-Host "Launching Microsoft Malicious Software Removal Tool: $found"
                try {
                    # Run interactive with default UI; MRT may be interactive and require user input
                    Start-Process -FilePath $found -ArgumentList '/Q' -Wait
                    Write-Host 'MMR completed or exited. Check event logs for details.'
                } catch {
                    Write-Host "Failed to run MMR: $($_.Exception.Message)"
                }
            } else {
                Write-Host 'mrt.exe not found on this system.'
            }
        } catch {
            Write-Host "Run MMR button failed: $($_.Exception.Message)"
        } finally {
            if (Get-Command -Name Invoke-WithDivider -ErrorAction SilentlyContinue) { Invoke-WithDivider -Action { } }
            else { if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider } }
        }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
