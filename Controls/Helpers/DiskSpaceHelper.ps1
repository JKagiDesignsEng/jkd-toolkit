<#
Controls\Helpers\DiskSpaceHelper.ps1

Purpose:
  Provides a small helper function to check available free disk space for a given
  path and compare it to a required byte count. Returns a hashtable with
  keys: Ok (bool), FreeBytes (int64), RequiredBytes (int64), Message (string).

Usage:
  . "$PSScriptRoot\Helpers\DiskSpaceHelper.ps1"
  $res = Test-FreeSpace -Path $env:TEMP -RequiredBytes 8GB
  if (-not $res.Ok) { Write-Host $res.Message }
#>

function Test-FreeSpace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$false)] [string] $Path = $env:TEMP,
        [Parameter(Mandatory=$true)] [int64] $RequiredBytes
    )

    $result = @{ Ok = $false; FreeBytes = 0; RequiredBytes = $RequiredBytes; Message = '' }
    try {
        # Resolve PSDrive root for the path
        $driveRoot = (Get-Item -Path $Path -ErrorAction Stop).PSDrive.Root
        $psname = $driveRoot.TrimEnd('\') -replace ':\\$',''
        $ps = Get-PSDrive -Name $psname -ErrorAction SilentlyContinue
        if ($ps -and $ps.Free -ne $null) {
            $free = [int64]$ps.Free
        } else {
            # Fallback to Get-Volume on the path
            $vol = Get-Volume -FilePath $Path -ErrorAction SilentlyContinue
            if ($vol) { $free = [int64]$vol.SizeRemaining } else { $free = 0 }
        }

        $result.FreeBytes = $free
        if ($free -ge $RequiredBytes) {
            $result.Ok = $true
            $result.Message = "Sufficient free space: $([math]::Round($free/1GB,2)) GB available."
        } else {
            $result.Ok = $false
            $result.Message = "Insufficient free space. Required: $([math]::Round($RequiredBytes/1GB,2)) GB, Available: $([math]::Round($free/1GB,2)) GB."
        }
    } catch {
        $result.Message = "Error checking free space: $($_.Exception.Message)"
    }

    return $result
}
