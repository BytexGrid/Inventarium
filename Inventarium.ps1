# Script by BytexGrid.
# This script is designed to fetch a comprehensive list of programs and tools installed on your Windows system.
# It gathers data from the Registry, winget, Chocolatey, and Scoop. Note: It is not yet perfect.

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host "Starting application discovery..." -ForegroundColor Cyan
Write-Host "This may take a moment as we query multiple sources."

$allApps = [System.Collections.Generic.List[pscustomobject]]::new()
$sourceCounts = @{ Registry = 0; winget = 0; Chocolatey = 0; Scoop = 0; Total = 0 }

function Add-AppToList {
    param([string]$Name, [string]$Version, [string]$Publisher, [string]$Source)
    $cleanName = if ([string]::IsNullOrWhiteSpace($Name)) { 'Unknown' } else { $Name.Trim() }
    $cleanVersion = if ([string]::IsNullOrWhiteSpace($Version)) { 'Unknown' } else { $Version.Trim() }
    $cleanPublisher = if ([string]::IsNullOrWhiteSpace($Publisher)) { 'Unknown' } else { $Publisher.Trim() }
    if ($cleanName -eq 'Unknown') { return } # We only skip if the name is unknown
    $allApps.Add([pscustomobject]@{ Name = $cleanName; Version = $cleanVersion; Publisher = $cleanPublisher; Source = $Source })
    $sourceCounts[$Source]++; $sourceCounts['Total']++
}

Write-Host "`n[1/4] Querying Windows Registry..." -ForegroundColor Yellow
try {
    $regPaths = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*', 'HKLM:\Software\Wow6432Node\Microsoft\Windows\Uninstall\*'
    Get-ItemProperty $regPaths -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.PSObject.Properties['DisplayName'] -and $_.DisplayName -notlike "Update for*") {
            Add-AppToList -Name $_.DisplayName -Version $_.DisplayVersion -Publisher $_.Publisher -Source "Registry"
        }
    }
} catch { Write-Warning "An error occurred while querying the Registry: $($_.Exception.Message)" }

# ==============================================================================
# UPDATED WINGET SECTION (Now with user permission + improved fallback parsing)
# ==============================================================================
Write-Host "[2/4] Querying winget..." -ForegroundColor Yellow
try {
    $useModule = $false
    # Check if the module is already available
    if (Get-Module -ListAvailable -Name Microsoft.WinGet.Client) {
        $useModule = $true
    } else {
        # If module is not found, ask the user for permission to install it
        Write-Host "`n✨ A BETTER METHOD IS AVAILABLE ✨" -ForegroundColor Cyan
        Write-Host "The official 'winget' PowerShell module provides more accurate, non-truncated app names."
        Write-Host "It's safe, published by Microsoft, and less than 20 MB to install."
        $choice = Read-Host "Do you want to install this module now for the best results? (y/n)"
        
        if ($choice -eq 'y') {
            Write-Host "Installing the module for the current user (this may take a moment)..." -ForegroundColor Gray
            Install-Module -Name Microsoft.WinGet.Client -Repository PSGallery -Force -Scope CurrentUser
            $useModule = $true
        } else {
            Write-Host "Module installation skipped." -ForegroundColor Yellow
            Write-Warning "Falling back to the standard command. NOTE: Application names may be truncated."
        }
    }

    if ($useModule) {
        # Method 1: Use the superior PowerShell Module
        Write-Host "Using the PowerShell module for winget..." -ForegroundColor Green
        Import-Module Microsoft.WinGet.Client
        $wingetApps = Get-WinGetPackage
        
        foreach ($app in $wingetApps) {
            $publisher = 'Unknown'
            if ($app.Id -like '*.*' -and $app.Id -notlike 'ARP*') {
                $publisher = ($app.Id).Split('.')[0]
            }
            Add-AppToList -Name $app.Name -Version $app.Version -Publisher $publisher -Source "winget"
        }
    } else {
        # Method 2: Fallback to the standard command-line tool (improved parsing)
        Write-Host "Using the fallback command-line tool for winget..." -ForegroundColor Yellow
        $wingetListOutput = winget list --disable-interactivity --accept-source-agreements | Out-String
        $lines = $wingetListOutput.Split([System.Environment]::NewLine)
        $headerLine = $lines | Select-String -Pattern 'Name\s+Id\s+Version' | Select-Object -First 1
        if (-not $headerLine) { throw "Could not find the header row in winget's text output." }
        $headerString = $headerLine.ToString()
        $idIndex = $headerString.IndexOf('Id'); $versionIndex = $headerString.IndexOf('Version')
        $availableIndex = $headerString.IndexOf('Available'); $sourceIndex = $headerString.IndexOf('Source')
        if ($idIndex -lt 0 -or $versionIndex -lt 0) { throw "Could not find required 'Id' and 'Version' columns." }
        $headerLineIndex = [array]::IndexOf($lines, $headerLine)
        for ($i = $headerLineIndex + 2; $i -lt $lines.Length; $i++) {
            $line = $lines[$i]
            if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt $versionIndex) { continue }
            $name = $line.Substring(0, $idIndex).Trim()
            $version = ''; $publisher = ''
            $versionLength = -1
            if ($availableIndex -gt $versionIndex) { $versionLength = $availableIndex - $versionIndex }
            elseif ($sourceIndex -gt $versionIndex) { $versionLength = $sourceIndex - $versionIndex }
            if ($versionLength -gt 0 -and ($versionIndex + $versionLength) -le $line.Length) {
                $version = $line.Substring($versionIndex, $versionLength).Trim()
            } elseif ($line.Length -gt $versionIndex) {
                $version = ($line.Substring($versionIndex).Trim() -split '\s+')[0]
            }
            if ($sourceIndex -gt 0 -and $line.Length -gt $sourceIndex) { $publisher = $line.Substring($sourceIndex).Trim() }
            if ([string]::IsNullOrWhiteSpace($publisher)) { $publisher = 'winget' }
            Add-AppToList -Name $name -Version $version -Publisher $publisher -Source "winget (fallback)"
        }
    }
} catch {
    Write-Warning "An error occurred during the winget query. Error: $($_.Exception.Message)"
}
# ==============================================================================
# END OF UPDATED SECTION
# ==============================================================================

Write-Host "[3/4] Querying Chocolatey..." -ForegroundColor Yellow
try {
    if (-not (Get-Command choco -ErrorAction SilentlyContinue)) { throw "Chocolatey (choco) command not found." }
    $chocoOutput = choco list --local-only --limit-output
    foreach ($line in $chocoOutput) {
        $parts = $line.Split('|')
        if ($parts.Length -eq 2) { Add-AppToList -Name $parts[0] -Version $parts[1] -Publisher "Chocolatey" -Source "Chocolatey" }
    }
} catch { Write-Warning "Could not get apps from Chocolatey. Is it installed? Error: $($_.Exception.Message)" }

Write-Host "[4/4] Querying Scoop..." -ForegroundColor Yellow
try {
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) { throw "Scoop command not found." }
    $scoopOutput = scoop list | Out-String
    $scoopLines = $scoopOutput.Split([System.Environment]::NewLine)
    foreach ($line in $scoopLines) {
        if ($line -match '^\s*$' -or $line.StartsWith('Installed apps:') -or $line.StartsWith('----') -or $line.Trim().StartsWith('Name')) { continue }
        $parts = $line.Trim() -split '\s+'
        if ($parts.Length -ge 2) { Add-AppToList -Name $parts[0] -Version $parts[1] -Publisher "Scoop" -Source "Scoop" }
    }
} catch { Write-Warning "Could not get apps from Scoop. Is it installed? Error: $($_.Exception.Message)" }

Write-Host "`nProcessing and deduplicating results..." -ForegroundColor Cyan
$deduplicatedList = $allApps | Group-Object -Property Name | ForEach-Object {
    $group = $_.Group
    $bestEntry = $group | Where-Object { $_.Source -eq 'Registry' } | Select-Object -First 1
    if (-not $bestEntry) { $bestEntry = $group | Where-Object { $_.Source -eq 'winget' } | Select-Object -First 1 }
    if (-not $bestEntry) { $bestEntry = $group | Select-Object -First 1 }
    $bestEntry
} | Sort-Object -Property Name

$finalList = $deduplicatedList | Select-Object Name, Version, Publisher, Source

# Try Out-GridView if available
$useGridView = $false
try {
    Get-Command Out-GridView -ErrorAction Stop | Out-Null
    $useGridView = $true
} catch {
    Write-Verbose "Out-GridView is not available, falling back to Format-Table"
}

if ($useGridView) {
    $finalList | Out-GridView -Title "Application Discovery Report"
    $finalList | Format-Table -AutoSize -Wrap
} else {
    $finalList | Format-Table -AutoSize -Wrap
}

Write-Host "`n"
Write-Host ("-" * 50) -ForegroundColor Green
Write-Host "▲ SCROLL UP TO VIEW THE COMPLETE LIST ABOVE ▲" -ForegroundColor Yellow -BackgroundColor DarkGray
Write-Host ("-" * 50) -ForegroundColor Green
Write-Host "`n"
Write-Host "-----------------------------------------" -ForegroundColor Green
Write-Host "           Application Discovery Report" -ForegroundColor Green
Write-Host "-----------------------------------------" -ForegroundColor Green
Write-Host "Items found per source (before deduplication):"
Write-Host "  - Registry:   $($sourceCounts.Registry)"
Write-Host "  - winget:     $($sourceCounts.winget)"
Write-Host "  - Chocolatey: $($sourceCounts.Chocolatey)"
Write-Host "  - Scoop:      $($sourceCounts.Scoop)"
Write-Host "-----------------------------------------"
Write-Host "Total initial entries found: $($sourceCounts.Total)"
Write-Host "Unique applications after deduplication: $($finalList.Count)" -ForegroundColor Yellow
Write-Host "`n"

try {
    $saveChoice = Read-Host "Do you want to save this list to a file? (y/n)"
    if ($saveChoice -eq 'y') {
        $formatChoice = Read-Host "Enter format (txt, json)"
        $fileName = Read-Host "Enter filename (e.g., my-apps)"
        $filePath = "$($env:USERPROFILE)\Desktop\$fileName.$formatChoice"

        switch ($formatChoice) {
            'txt' { $finalList | Out-File -FilePath $filePath -Encoding utf8 }
            'json' { $finalList | ConvertTo-Json -Depth 3 | Out-File -FilePath $filePath -Encoding utf8 }
            default { Write-Warning "Invalid format. File not saved."; return }
        }
        Write-Host "File saved successfully to your Desktop: $filePath" -ForegroundColor Green
    }
} catch {
    Write-Warning "An error occurred while trying to save the file: $($_.Exception.Message)"
}

Write-Host "`nPress Enter to exit..." -ForegroundColor Cyan
$null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
