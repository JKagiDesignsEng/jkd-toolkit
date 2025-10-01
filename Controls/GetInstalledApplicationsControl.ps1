<#
Provides a DataGridView that lists installed applications and allows the user to
select rows to uninstall, search for packages via `winget` or `choco` and install
selected packages. All operational output is printed to the console per project
preference.

Usage:
    . "$PSScriptRoot\Controls\GetInstalledApplicationsControl.ps1"
    Add-GetInstalledApplicationsControl -Parent $tabApps -Location (New-Object System.Drawing.Point(10,10)) -Size (New-Object System.Drawing.Size(940,380))

Notes:
    - Uninstall/Install will invoke shell commands (winget/choco/msiexec) which may
        require elevation. The control prints progress to console; the UI does not show
        interactive popups. Use with care.
#>

# Disable approved-verb warnings for this UI control script where verbs are chosen for readability
# PSScriptAnalyzer disable=PSUseApprovedVerbs

function Get-InstalledAppsFromRegistry {
    # Read from common uninstall registry keys (both 64-bit and 32-bit views)
    $hives = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall'
    )
    $apps = @()
    foreach ($h in $hives) {
        if (Test-Path $h) {
            Get-ChildItem -Path $h -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $props = Get-ItemProperty -Path $_.PsPath -ErrorAction Stop
                    if ($props.DisplayName) {
                        $apps += [pscustomobject]@{
                            Name = $props.DisplayName
                            Version = $props.DisplayVersion
                            Publisher = $props.Publisher
                            InstallLocation = $props.InstallLocation
                            UninstallString = $props.UninstallString
                            Source = 'Registry'
                        }
                    }
                } catch { }
            }
        }
    }
    return $apps | Sort-Object Name -Unique
}

function Get-WingetList {
    try {
        if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { return @() }
        $out = & winget list --source winget --accept-package-agreements --accept-source-agreements 2>$null | Out-String
        # winget list output is tabular: parse simplisticly
        $lines = $out -split "`n" | Where-Object { $_ -and ($_ -notmatch '^-+') }
        $results = @()
        foreach ($l in $lines) {
            $parts = $l -split '\s{2,}' | ForEach-Object { $_.Trim() }
            if ($parts.Count -ge 1) {
                $name = $parts[0]
                $ver = if ($parts.Count -ge 2) { $parts[1] } else { $null }
                $results += [pscustomobject]@{ Name = $name; Version = $ver; Publisher = ''; Source='winget' }
            }
        }
        return $results | Sort-Object Name -Unique
    } catch {
        return @()
    }
}

function Find-PackageViaWingetOrChoco {
    param(
        [Parameter(Mandatory=$true)][string]$Term
    )

    $results = New-Object System.Collections.ArrayList
    $hasWinget = Get-Command winget -ErrorAction SilentlyContinue
    $hasChoco  = Get-Command choco  -ErrorAction SilentlyContinue

    if ($hasWinget) {
        try {
            # Prefer JSON output when available
            $raw = (& winget search --name $Term --output json 2>$null) -join "`n"
            if ($raw -and $raw.TrimStart() -match '^[\[\{]') {
                $json = $raw | ConvertFrom-Json
                foreach ($entry in $json) {
                    $id = $null
                    if ($entry.PSObject.Properties.Match('Id')) { $id = $entry.Id }
                    elseif ($entry.PSObject.Properties.Match('PackageIdentifier')) { $id = $entry.PackageIdentifier }
                    $ver = $null
                    if ($entry.PSObject.Properties.Match('Versions')) {
                        try { $ver = ($entry.Versions | Select-Object -First 1).Version } catch { $ver = $null }
                    } elseif ($entry.PSObject.Properties.Match('Version')) { $ver = $entry.Version }
                    [void]$results.Add([pscustomobject]@{ Name=$entry.Name; Id=$id; Version=$ver; Source='winget' })
                }
            } else {
                # Fallback: parse text table output
                $text = (& winget search $Term 2>$null) -join "`n"
                if ($text) {
                    $lines = $text -split "`n" | ForEach-Object { $_.TrimEnd() } |
                        Where-Object { $_ -and ($_ -notmatch '^-+' -and $_ -notmatch '^(Name|Id|Package|Version|Source)\b' -and $_ -notmatch '^Windows') }
                    foreach ($l in $lines) {
                        $parts = [regex]::Split($l, '\s{2,}') | ForEach-Object { $_.Trim() }
                        if ($parts.Count -ge 1) {
                            $name = $parts[0]
                            $id   = if ($parts.Count -ge 2) { $parts[1] } else { $null }
                            $ver  = if ($parts.Count -ge 3) { $parts[2] } else { $null }
                            if ($name -and $name.Length -gt 1) {
                                [void]$results.Add([pscustomobject]@{ Name=$name; Id=$id; Version=$ver; Source='winget' })
                            }
                        }
                    }
                }
            }
        } catch {
            Write-Host "winget search failed: $($_.Exception.Message)"
        }
    }

    if ($hasChoco) {
        try {
            $raw = (& choco search $Term --limit-output 2>$null) -join "`n"
            $lines = $raw -split "`n" | Where-Object { $_ -and ($_ -notmatch '^Chocolatey') }
            foreach ($l in $lines) {
                $nm = $l.Trim()
                if ($nm) { [void]$results.Add([pscustomobject]@{ Name=$nm; Version=''; Source='choco' }) }
            }
        } catch {
            Write-Host "choco search failed: $($_.Exception.Message)"
        }
    }

    if ($results.Count -gt 0) { return $results | Sort-Object Name -Unique }
    Write-Host "No package manager (winget/choco) found on PATH or no results."
    return @()
}

function Add-GetInstalledApplicationsControl {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,10)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(900,360))
    )

    # Container panel
        # Defensive: sometimes callers (or piping) can cause $Size to be an array; normalize to a single System.Drawing.Size
        if ($null -ne $Size -and $Size -is [System.Array]) {
            # If an array of sizes was passed, take the first element that is a Size or try to construct one from numbers
            $first = $Size | Where-Object { $_ -is [System.Drawing.Size] } | Select-Object -First 1
            if (-not $first) {
                # Try take numeric width/height from first element
                $maybe = $Size[0]
                if ($maybe -is [string]) {
                    $parts = $maybe -split '[,x ]' | Where-Object { $_ -match '\d+' }
                    if ($parts.Count -ge 2) { $first = New-Object System.Drawing.Size([int]$parts[0], [int]$parts[1]) }
                } elseif ($maybe -is [int[]] -or $maybe -is [long[]]) {
                    if ($maybe.Count -ge 2) { $first = New-Object System.Drawing.Size([int]$maybe[0], [int]$maybe[1]) }
                }
            }
            if ($first) { $Size = $first } else { $Size = New-Object System.Drawing.Size(900,360) }
        }

    $panel = New-Object System.Windows.Forms.Panel
    # Stable name so runtime lookups can find the panel if closures aren't available
    $panel.Name = 'panelApps'
        $panel.Location = $Location
        $panel.Size = $Size
    $panel.BorderStyle = 'FixedSingle'

    # Search row
    $txtSearch = New-Object System.Windows.Forms.TextBox
    $txtSearch.Name = 'txtSearch'
    $txtSearch.Size = New-Object System.Drawing.Size(540,24)
    $txtSearch.Location = New-Object System.Drawing.Point(10,10)
    $panel.Controls.Add($txtSearch)

    $btnSearch = New-Object System.Windows.Forms.Button
    $btnSearch.Name = 'btnSearch'
    $btnSearch.Text = 'Search (winget/choco)'
    $btnSearch.Size = New-Object System.Drawing.Size(160,24)
    $btnSearch.Location = New-Object System.Drawing.Point(560,10)
    $panel.Controls.Add($btnSearch)

    # Store reference to the parent panel on buttons so handlers can reliably find sibling controls
    $btnSearch.Tag = $panel

    $btnClear = New-Object System.Windows.Forms.Button
    $btnClear.Name = 'btnClear'
    $btnClear.Text = 'Clear'
    $btnClear.Size = New-Object System.Drawing.Size(80,24)
    $btnClear.Location = New-Object System.Drawing.Point(730,10)
    $panel.Controls.Add($btnClear)
    $btnClear.Tag = $panel

    # Installed button to repopulate with locally installed applications
    $btnInstalled = New-Object System.Windows.Forms.Button
    $btnInstalled.Name = 'btnInstalled'
    $btnInstalled.Text = 'Installed'
    $btnInstalled.Size = New-Object System.Drawing.Size(90,24)
    $btnInstalled.Location = New-Object System.Drawing.Point(815,10)
    $panel.Controls.Add($btnInstalled)
    $btnInstalled.Tag = $panel

    # DataGridView for installed apps / search results
    $dgv = New-Object System.Windows.Forms.DataGridView
    # Give the grid a stable name so event handlers can find it reliably at runtime
    $dgv.Name = 'dgvApps'
    # Tag the grid with the panel for quick owner lookup from event sender
    $dgv.Tag = $panel
    $dgv.Location = New-Object System.Drawing.Point(10,44)
    # Ensure Width/Height are integers before arithmetic
    $w = [int]($Size.Width)
    $h = [int]($Size.Height)
    $dgv.Size = New-Object System.Drawing.Size([int]($w - 20), [int]($h - 100))
    $dgv.ReadOnly = $false
    $dgv.AllowUserToAddRows = $false
    $dgv.SelectionMode = 'FullRowSelect'
    $dgv.MultiSelect = $true
    $dgv.AutoGenerateColumns = $false

    # Columns
    $colSel = New-Object System.Windows.Forms.DataGridViewCheckBoxColumn
    $colSel.HeaderText = 'Select'
    $colSel.Width = 50
    $dgv.Columns.Add($colSel)

    $colName = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colName.HeaderText = 'Name'
    $colName.DataPropertyName = 'Name'
    $colName.Width = 420
    $dgv.Columns.Add($colName)

    $colVer = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colVer.HeaderText = 'Version'
    $colVer.DataPropertyName = 'Version'
    $colVer.Width = 140
    $dgv.Columns.Add($colVer)

    $colSrc = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colSrc.HeaderText = 'Source'
    $colSrc.DataPropertyName = 'Source'
    $colSrc.Width = 120
    $dgv.Columns.Add($colSrc)

    # Hidden columns for internal use (Id from winget, UninstallString from registry)
    $colId = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colId.HeaderText = 'Id'
    $colId.DataPropertyName = 'Id'
    $colId.Visible = $false
    $dgv.Columns.Add($colId)

    $colUninst = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $colUninst.HeaderText = 'UninstallString'
    $colUninst.DataPropertyName = 'UninstallString'
    $colUninst.Visible = $false
    $dgv.Columns.Add($colUninst)

    $panel.Controls.Add($dgv)

    # Install/Uninstall buttons
    $btnInstall = New-Object System.Windows.Forms.Button
    $btnInstall.Name = 'btnInstall'
    $btnInstall.Text = 'Install Selected'
    $btnInstall.Size = New-Object System.Drawing.Size(140,28)
    $btnInstall.Location = New-Object System.Drawing.Point(10, [int]($h - 44))
    $btnInstall.Enabled = $false
    $panel.Controls.Add($btnInstall)

    $btnUninstall = New-Object System.Windows.Forms.Button
    $btnUninstall.Name = 'btnUninstall'
    $btnUninstall.Text = 'Uninstall Selected'
    $btnUninstall.Size = New-Object System.Drawing.Size(140,28)
    $btnUninstall.Location = New-Object System.Drawing.Point(160, [int]($h - 44))
    $btnUninstall.Enabled = $false
    $panel.Controls.Add($btnUninstall)

    # Helper: load installed apps into grid
    $appList = New-Object 'System.Collections.Generic.List[object]'
    # Store a reference to the list on the panel so handlers can recover it if closures misbehave
    $panel.Tag = @{ appList = $appList }
    function Update-InstalledAppsList {
        try {
            # Prefer the local $appList if present - it's the most direct reference
            $alist = $null
            if ($appList) { $alist = $appList }
            elseif ($panel -and $panel.Tag -and $panel.Tag.appList) { $alist = $panel.Tag.appList }
            else {
                # Try to find any panelApps in open forms
                foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                    $p = $f.Controls.Find('panelApps', $true)
                    if ($p -and $p.Count -gt 0 -and $p[0].Tag -and $p[0].Tag.appList) { $alist = $p[0].Tag.appList; break }
                }
            }
            if (-not $alist) { return }
            $alist.Clear()
            $regApps = Get-InstalledAppsFromRegistry
            foreach ($a in $regApps) { $alist.Add($a) }

            # Find a DataGridView named dgvApps to bind; prefer local $dgv if available
            $grid = $null
            if ($dgv) { $grid = $dgv }
            else {
                foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                    $g = $f.Controls.Find('dgvApps', $true)
                    if ($g -and $g.Count -gt 0) { $grid = $g[0]; break }
                }
            }
            if ($grid) { $grid.DataSource = $null; $grid.DataSource = $alist }
    } catch { }
    }

    # Selection state update
    $updateButtons = {
        try {
            # Attempt to find the DataGridView across open forms in case closures are invalid
            $local = $null
            foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                $g = $f.Controls.Find('dgvApps', $true)
                if ($g -and $g.Count -gt 0) { $local = $g[0]; break }
            }
            if (-not $local) { return }
            $selected = $local.Rows | Where-Object { $_.Cells[0].Value -eq $true }
            $has = ($selected.Count -gt 0)
            # Find install/uninstall buttons relative to the grid's parent if possible
            $parent = $local.Parent
            if ($parent) {
                $btnI = $parent.Controls.Find('btnInstall', $true)
                $btnU = $parent.Controls.Find('btnUninstall', $true)
                if ($btnI -and $btnI.Count -gt 0) { $btnI[0].Enabled = $has }
                if ($btnU -and $btnU.Count -gt 0) { $btnU[0].Enabled = $has }
            }
    } catch { }
    }

    # NOTE: we avoid defining helpers that event handlers may not see; handlers inline the update logic below.

    # Wire events: when cell checkbox toggled - inline update logic so event runs without external function dependencies
    $dgv.Add_CellValueChanged({
        try {
            $local = $null
            foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                $g = $f.Controls.Find('dgvApps', $true)
                if ($g -and $g.Count -gt 0) { $local = $g[0]; break }
            }
            if (-not $local) { return }
            $selected = $local.Rows | Where-Object { $_.Cells[0].Value -eq $true }
            $has = ($selected.Count -gt 0)
            $parent = $local.Parent
            if ($parent) {
                $btnI = $parent.Controls.Find('btnInstall', $true)
                $btnU = $parent.Controls.Find('btnUninstall', $true)
                if ($btnI -and $btnI.Count -gt 0) { $btnI[0].Enabled = $has }
                if ($btnU -and $btnU.Count -gt 0) { $btnU[0].Enabled = $has }
            }
    } catch { }
    })
    $dgv.Add_CurrentCellDirtyStateChanged({ param($s,$e)
        try {
            # Prefer the sender as the DataGridView
            $local = $null
            if ($s -and $s -is [System.Windows.Forms.DataGridView]) {
                $local = $s
            } else {
                # Fallback: try finding by name within open forms
                foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                    $g = $f.Controls.Find('dgvApps', $true)
                    if ($g -and $g.Count -gt 0) { $local = $g[0]; break }
                }
            }
            if ($local -and $local.IsCurrentCellDirty) {
                $local.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit)
            }
        } catch { }
    })

    # Clear action
    $btnClear.Add_Click({ param($s,$e)
        $owner = $s.Tag
        if (-not $owner) { $owner = $s.Parent }
        $txt = $null
        if ($owner) { $found = $owner.Controls.Find('txtSearch', $true); if ($found -and $found.Count -gt 0) { $txt = $found[0] } }
        if (-not $txt) {
            # Try to find any txtSearch in open forms as a last resort
            foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                $t = $f.Controls.Find('txtSearch', $true)
                if ($t -and $t.Count -gt 0) { $txt = $t[0]; break }
            }
        }
        if ($txt) { $txt.Text = '' }

        # Clear grid if found
        $grid = $null
        foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
            $g = $f.Controls.Find('dgvApps', $true)
            if ($g -and $g.Count -gt 0) { $grid = $g[0]; break }
        }
    if ($grid) { $grid.DataSource = $null }

        # Try to recover appList from owner.Tag or any panelApps
        $alist = $null
        if ($owner -and $owner.Tag -and $owner.Tag.appList) { $alist = $owner.Tag.appList }
        if (-not $alist) {
            foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                $p = $f.Controls.Find('panelApps', $true)
                if ($p -and $p.Count -gt 0 -and $p[0].Tag -and $p[0].Tag.appList) { $alist = $p[0].Tag.appList; break }
            }
        }
    if ($alist) { try { $alist.Clear() } catch { } }
    # Inline update buttons logic
    try {
            $local = $null
            foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                $g = $f.Controls.Find('dgvApps', $true)
                if ($g -and $g.Count -gt 0) { $local = $g[0]; break }
            }
            if ($local) {
                $selected = $local.Rows | Where-Object { $_.Cells[0].Value -eq $true }
                $has = ($selected.Count -gt 0)
                $parent = $local.Parent
                if ($parent) {
                    $btnI = $parent.Controls.Find('btnInstall', $true)
                    $btnU = $parent.Controls.Find('btnUninstall', $true)
                    if ($btnI -and $btnI.Count -gt 0) { $btnI[0].Enabled = $has }
                    if ($btnU -and $btnU.Count -gt 0) { $btnU[0].Enabled = $has }
                }
            }
    } catch { 
        Write-Host 'Cleared search/results.'
            } finally {
                if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
            }
        })

    # Search action
    $btnSearch.Add_Click({ param($s,$e)
        try {
        $owner = $s.Tag
        if (-not $owner) { $owner = $s.Parent }
        $txt = $null
        if ($owner) { $found = $owner.Controls.Find('txtSearch', $true); if ($found -and $found.Count -gt 0) { $txt = $found[0] } }
        if (-not $txt) {
            foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                $t = $f.Controls.Find('txtSearch', $true)
                if ($t -and $t.Count -gt 0) { $txt = $t[0]; break }
            }
        }
        $term = if ($txt) { $txt.Text.Trim() } else { '' }
        if (-not $term) { Write-Host 'Enter a search term first.'; return }

        # Debug: report control types before searching
        $localDgv = $null
        foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
            $g = $f.Controls.Find('dgvApps', $true)
            if ($g -and $g.Count -gt 0) { $localDgv = $g[0]; break }
        }
    # optional: could log type; suppressing debug output
        $alist = $null
        if ($owner -and $owner.Tag -and $owner.Tag.appList) { $alist = $owner.Tag.appList } elseif ($panel -and $panel.Tag -and $panel.Tag.appList) { $alist = $panel.Tag.appList } elseif ($appList) { $alist = $appList }
    # suppress debug appList count

        $results = Find-PackageViaWingetOrChoco -Term $term
        if (-not $results -or $results.Count -eq 0) { Write-Host "No results for '$term'"; return }

        # Map results to objects with Name/Version/Source
    if ($localDgv) { $localDgv.DataSource = $null }
    if (-not $alist) { return }
        try {
            $alist.Clear()
            foreach ($r in $results) { $alist.Add($r) }
            if ($localDgv) { $localDgv.DataSource = $alist }
    } catch { }
        # Inline update buttons logic
        try {
            $local = $null
            foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                $g = $f.Controls.Find('dgvApps', $true)
                if ($g -and $g.Count -gt 0) { $local = $g[0]; break }
            }
            if ($local) {
                $selected = $local.Rows | Where-Object { $_.Cells[0].Value -eq $true }
                $has = ($selected.Count -gt 0)
                $parent = $local.Parent
                if ($parent) {
                    $btnI = $parent.Controls.Find('btnInstall', $true)
                    $btnU = $parent.Controls.Find('btnUninstall', $true)
                    if ($btnI -and $btnI.Count -gt 0) { $btnI[0].Enabled = $has }
                    if ($btnU -and $btnU.Count -gt 0) { $btnU[0].Enabled = $has }
                }
            }
    } catch { }
        } finally {
            if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
        }
    })

    # Installed action: reload installed apps into the grid
    $btnInstalled.Add_Click({ param($s,$e)
        try {
            $owner = $s.Tag; if (-not $owner) { $owner = $s.Parent }
            # Locate grid
            $grid = $null
            foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                $g = $f.Controls.Find('dgvApps', $true)
                if ($g -and $g.Count -gt 0) { $grid = $g[0]; break }
            }
            if (-not $grid) { return }

            # Use panel's appList if available, else create one
            $alist = $null
            if ($owner -and $owner.Tag -and $owner.Tag.appList) { $alist = $owner.Tag.appList }
            if (-not $alist) { $alist = New-Object 'System.Collections.Generic.List[object]'; if ($owner) { $owner.Tag = @{ appList = $alist } } }

            # Populate with installed apps
            $alist.Clear()
            $regApps = Get-InstalledAppsFromRegistry
            foreach ($a in $regApps) { $alist.Add($a) }
            $grid.DataSource = $null; $grid.DataSource = $alist

            # Disable action buttons until selection
            $parent = $grid.Parent
            if ($parent) {
                $btnI = $parent.Controls.Find('btnInstall', $true)
                $btnU = $parent.Controls.Find('btnUninstall', $true)
                if ($btnI -and $btnI.Count -gt 0) { $btnI[0].Enabled = $false }
                if ($btnU -and $btnU.Count -gt 0) { $btnU[0].Enabled = $false }
            }
            Write-Host 'Loaded installed applications.'
        } catch { } finally {
            if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
        }
    })

    # Install action
    $btnInstall.Add_Click({ param($s,$e)
        try {
        # Locate the grid from the sender's owner or via OpenForms fallback
        $grid = $null
        try {
            $owner = $null
            if ($s -and $s.Tag) { $owner = $s.Tag } elseif ($s) { $owner = $s.Parent }
            if ($owner) {
                $found = $owner.Controls.Find('dgvApps', $true)
                if ($found -and $found.Count -gt 0) { $grid = $found[0] }
            }
            if (-not $grid) {
                foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                    $g = $f.Controls.Find('dgvApps', $true)
                    if ($g -and $g.Count -gt 0) { $grid = $g[0]; break }
                }
            }
    } catch { }
    if (-not $grid) { return }

        # Ensure any pending checkbox edit is committed before reading selection
        try {
            if ($grid.IsCurrentCellDirty) { $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) }
            $grid.EndEdit()
    } catch { }

        # Robustly gather checked rows from the first (checkbox) column
        $selected = @()
        try {
            for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
                $row = $grid.Rows[$i]
                if ($null -ne $row -and $row.Cells.Count -gt 0) {
                    $val = $row.Cells[0].Value
                    if (($val -is [bool] -and $val) -or $val -eq $true) { $selected += $row }
                }
            }
    } catch { }
        if ($selected.Count -eq 0) { Write-Host 'No packages selected to install.'; return }
        foreach ($row in $selected) {
            $item = $row.DataBoundItem
            $name = $item.Name
            $source = $item.Source
            $id = if ($item.PSObject.Properties.Match('Id')) { $item.Id } else { $null }
            Write-Host "Installing $name (source: $source; id: $id)..."
            if ($source -eq 'winget' -and (Get-Command winget -ErrorAction SilentlyContinue)) {
                if ($id) {
                    Write-Host "Running: winget install --id '$id' --accept-package-agreements --accept-source-agreements"
                    & winget install --id $id --accept-package-agreements --accept-source-agreements
                } else {
                    Write-Host "Running: winget install --name '$name' --accept-package-agreements --accept-source-agreements"
                    & winget install --name $name --accept-package-agreements --accept-source-agreements
                }
            } elseif ($source -eq 'choco' -and (Get-Command choco -ErrorAction SilentlyContinue)) {
                Write-Host "Running: choco install $name -y"
                & choco install $name -y
            } else {
                Write-Host "No supported installer for $name (source: $source)."
            }
        }
        # After install attempts, refresh installed list inline (event handlers cannot see local functions reliably)
        try {
            $panelRef = $null
            if ($grid -and $grid.Tag -is [System.Windows.Forms.Control]) { $panelRef = $grid.Tag }
            $alist = $null
            if ($panelRef -and $panelRef.Tag -and $panelRef.Tag.appList) { $alist = $panelRef.Tag.appList }
            if (-not $alist) {
                $alist = New-Object 'System.Collections.Generic.List[object]'
                if ($panelRef) { $panelRef.Tag = @{ appList = $alist } }
            }
            $alist.Clear()
            $regApps = Get-InstalledAppsFromRegistry
            foreach ($a in $regApps) { $alist.Add($a) }
            if ($grid) { $grid.DataSource = $null; $grid.DataSource = $alist }
        } catch { }
        } finally {
            if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
        }
    })

    # Uninstall action
    $btnUninstall.Add_Click({ param($s,$e)
        try {
        # Locate the grid from the sender's owner or via OpenForms fallback
        $grid = $null
        try {
            $owner = $null
            if ($s -and $s.Tag) { $owner = $s.Tag } elseif ($s) { $owner = $s.Parent }
            if ($owner) {
                $found = $owner.Controls.Find('dgvApps', $true)
                if ($found -and $found.Count -gt 0) { $grid = $found[0] }
            }
            if (-not $grid) {
                foreach ($f in [System.Windows.Forms.Application]::OpenForms) {
                    $g = $f.Controls.Find('dgvApps', $true)
                    if ($g -and $g.Count -gt 0) { $grid = $g[0]; break }
                }
            }
    } catch { }
    if (-not $grid) { return }

        # Ensure any pending checkbox edit is committed before reading selection
        try {
            if ($grid.IsCurrentCellDirty) { $grid.CommitEdit([System.Windows.Forms.DataGridViewDataErrorContexts]::Commit) }
            $grid.EndEdit()
    } catch { }

        # Robustly gather checked rows from the first (checkbox) column
        $selected = @()
        try {
            for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
                $row = $grid.Rows[$i]
                if ($null -ne $row -and $row.Cells.Count -gt 0) {
                    $val = $row.Cells[0].Value
                    if (($val -is [bool] -and $val) -or $val -eq $true) { $selected += $row }
                }
            }
    } catch { }
        if ($selected.Count -eq 0) { Write-Host 'No applications selected to uninstall.'; return }
        foreach ($row in $selected) {
            $item = $row.DataBoundItem
            $name = $item.Name
            $id = if ($item.PSObject.Properties.Match('Id')) { $item.Id } else { $null }
            $unstr = if ($item.PSObject.Properties.Match('UninstallString')) { $item.UninstallString } else { $null }
            Write-Host "Attempting uninstall of $name (id: $id)..."
            if ($unstr) {
                Write-Host "Running: $unstr"
                try { Start-Process -FilePath 'cmd.exe' -ArgumentList "/c", $unstr -Wait -NoNewWindow } catch { Write-Host "Failed to run uninstall string: $($_.Exception.Message)" }
            } else {
                Write-Host "No uninstall string available for $name; attempting winget uninstall if available..."
                if (Get-Command winget -ErrorAction SilentlyContinue) {
                    if ($id) {
                        & winget uninstall --id $id --accept-package-agreements --accept-source-agreements
                    } else {
                        & winget uninstall --name $name --accept-package-agreements --accept-source-agreements
                    }
                } else {
                    Write-Host "No automatic uninstall available for $name."
                }
            }
        }
        # After uninstall attempts, refresh installed list inline
        try {
            $panelRef = $null
            if ($grid -and $grid.Tag -is [System.Windows.Forms.Control]) { $panelRef = $grid.Tag }
            $alist = $null
            if ($panelRef -and $panelRef.Tag -and $panelRef.Tag.appList) { $alist = $panelRef.Tag.appList }
            if (-not $alist) {
                $alist = New-Object 'System.Collections.Generic.List[object]'
                if ($panelRef) { $panelRef.Tag = @{ appList = $alist } }
            }
            $alist.Clear()
            $regApps = Get-InstalledAppsFromRegistry
            foreach ($a in $regApps) { $alist.Add($a) }
            if ($grid) { $grid.DataSource = $null; $grid.DataSource = $alist }
        } catch { }
        } finally {
            if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
        }
    })

    # Initialize installed app listing: populate local appList and bind immediately to the local grid.
    try {
        $appList.Clear()
        $regApps = Get-InstalledAppsFromRegistry
        foreach ($a in $regApps) { $appList.Add($a) }
        if ($dgv) { $dgv.DataSource = $appList }
    else { }
    } catch { }

    $Parent.Controls.Add($panel)
    return $panel
}

