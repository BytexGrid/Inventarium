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
    if ($cleanName -eq 'Unknown' -or $cleanVersion -eq 'Unknown') { return }
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

Write-Host "[2/4] Querying winget..." -ForegroundColor Yellow
try {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget command not found." }
    $wingetRawJsonOutput = winget list --json --disable-interactivity --accept-source-agreements 2>&1 | Out-String
    $wingetApps = $null
    if ($wingetRawJsonOutput -match '(?s)(\[.*\])') {
        $cleanJson = $matches[1]
        try { $wingetApps = $cleanJson | ConvertFrom-Json -ErrorAction Stop } catch {
            $wingetApps = $null
            Write-Warning "Found JSON-like text from winget, but it was invalid. Falling back to text parsing. Error: $($_.Exception.Message)"
        }
    }
    if ($wingetApps) {
        Write-Host "  (using reliable JSON output)"
        foreach ($app in $wingetApps) { Add-AppToList -Name $app.Name -Version $app.Version -Publisher $app.Source -Source "winget" }
    } else {
        Write-Host "  (JSON method failed, falling back to standard text parsing)"
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
            Add-AppToList -Name $name -Version $version -Publisher $publisher -Source "winget"
        }
    }
} catch { Write-Warning "Could not get apps from winget. Is it installed and in your PATH? Error: $($_.Exception.Message)" }

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
    # Test if Out-GridView is available
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
Write-Host "      Application Discovery Report" -ForegroundColor Green
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
 
