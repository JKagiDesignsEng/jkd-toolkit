<#
Controls\WallpaperControl.ps1

Purpose:
  Adds a button that opens a file dialog to choose an image and sets it as the desktop
  wallpaper for the current user using SystemParametersInfo.
#>

function Add-WallpaperButton {
    param(
        [Parameter(Mandatory=$true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory=$false)][System.Drawing.Point]$Location = $(New-Object System.Drawing.Point(10,220)),
        [Parameter(Mandatory=$false)][System.Drawing.Size]$Size = $(New-Object System.Drawing.Size(160,40))
    )

    Add-Type -MemberDefinition @'
    [DllImport("user32.dll", SetLastError=true)]
    public static extern bool SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@ -Name 'NativeMethods' -Namespace 'Win32' -ErrorAction SilentlyContinue

    $SPI_SETDESKWALLPAPER = 20
    $SPIF_UPDATEINIFILE = 0x01
    $SPIF_SENDCHANGE = 0x02

    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = 'Set Wallpaper'
    $btn.Size = $Size
    $btn.Location = $Location
    # Tooltip: plain-language explanation
    $tt = New-Object System.Windows.Forms.ToolTip
    $tt.AutoPopDelay = 20000
    $tt.InitialDelay = 500
    $tt.ReshowDelay = 100
    $tt.ShowAlways = $true
    $tt.SetToolTip($btn, "Opens a file dialog to choose an image and sets it as your desktop background. Supports common image types like JPG, PNG, and BMP. The change applies for the current user.")
    $btn.Tag = @{ ToolTip = $tt }

    $btn.Add_Click({
        try {
            $ofd = New-Object System.Windows.Forms.OpenFileDialog
            $ofd.Filter = 'Image Files|*.bmp;*.jpg;*.jpeg;*.png;*.gif|All Files|*.*'
            if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                $path = $ofd.FileName
                # SystemParametersInfo prefers BMP on some systems; but modern Windows accepts JPG/PNG
                [Win32.NativeMethods]::SystemParametersInfo($SPI_SETDESKWALLPAPER, 0, $path, $SPIF_UPDATEINIFILE -bor $SPIF_SENDCHANGE) | Out-Null
                Write-Host "Wallpaper set to $path"
            }
        } catch {
            Write-Host "Error setting wallpaper: $($_.Exception.Message)"
        } finally {
            if (Get-Command -Name Write-AsciiDivider -ErrorAction SilentlyContinue) { Write-AsciiDivider }
        }
    })

    $Parent.Controls.Add($btn)
    return $btn
}
