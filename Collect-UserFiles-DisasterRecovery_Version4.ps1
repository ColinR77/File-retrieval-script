<#
.SYNOPSIS
    Disaster Recovery File Gathering Script - Simplified
    
.DESCRIPTION
    Collects user files for disaster recovery with reliable folder selection.
    Excludes cloud storage (OneDrive, Google Drive, etc.) and system folders.
#>

param(
    [string]$DestinationPath,
    [switch]$SkipDriveCheck,
    [switch]$SkipVerification
)

# File extensions "Add to these as needed"
$fileExtensions = @{
    "Documents" = @("*.doc", "*.docx", "*.pdf", "*.txt", "*.xlsx", "*.xls", "*.pptx", "*.ppt", "*.odt", "*.rtf")
    "Images" = @("*.jpg", "*.jpeg", "*.png", "*.gif", "*.bmp", "*.tiff", "*.svg", "*.webp")
    "Videos" = @("*.mp4", "*.avi", "*.mkv", "*.mov", "*.wmv", "*.flv", "*.webm")
    "Spreadsheets" = @("*.xlsx", "*.xls", "*.csv", "*.ods")
    "Audio" = @("*.mp3", "*.wav", "*.flac", "*.aac", "*.ogg", "*.m4a")
    "Archives" = @("*.zip", "*.rar", "*.7z", "*.tar", "*.gz")
}

# Search paths
$searchPaths = @(
    [Environment]::GetFolderPath('MyDocuments'),
    [Environment]::GetFolderPath('MyPictures'),
    [Environment]::GetFolderPath('MyVideos'),
    [Environment]::GetFolderPath('Desktop'),
    [Environment]::GetFolderPath('UserProfile') + "\Downloads"
)

# IMPORTANT: Folders to EXCLUDE (cloud storage and system folders)
$excludeFolders = @(
    'AppData',
    'RECYCLE.BIN',
    '.git',
    'node_modules',
    '.cache',
    'Temp',
    'tmp',
    'OneDrive',
    'OneDrive - Personal',
    'OneDrive - Business',
    'Google Drive',
    'Dropbox',
    'iCloud',
    'SkyDrive',
    'box',
    'MicrosoftEdgeBackups',
    'Windows',
    'ProgramData',
    'Program Files',
    'ProgramFiles(x86)',
    'System32',
    'SysWOW64',
    'Boot',
    'Recovery',
    '.vscode',
    'node_modules',
    '__pycache__',
    '.nuget',
    '.m2',
    '.gradle',
    'packages',
    'vendor',
    '.dvc'
)

$script:copiedFiles = @()
$script:failedFiles = @()

function Get-DestinationPath {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  Enter destination path for backup files                   ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "Examples:" -ForegroundColor Cyan
    Write-Host "  E:\" -ForegroundColor Yellow
    Write-Host "  D:\Backups\" -ForegroundColor Yellow
    Write-Host "  C:\Users\$env:USERNAME\LocalBackups\" -ForegroundColor Yellow
    Write-Host ""
    
    $path = Read-Host "Enter destination path"
    
    if ([string]::IsNullOrWhiteSpace($path)) {
        Write-Host "No path entered. Exiting." -ForegroundColor Red
        exit
    }
    
    # Remove quotes if present
    $path = $path.Trim('"').Trim("'")
    
    # Create directory if it doesn't exist
    if (-not (Test-Path -Path $path)) {
        try {
            Write-Host "Creating directory: $path" -ForegroundColor Cyan
            New-Item -ItemType Directory -Path $path -Force | Out-Null
            Write-Host "Directory created" -ForegroundColor Green
        }
        catch {
            Write-Host "Error creating directory: $_" -ForegroundColor Red
            exit
        }
    }
    
    return $path
}

function Should-SkipFolder {
    param([string]$FolderPath)
    
    $folderName = Split-Path -Path $FolderPath -Leaf
    
    foreach ($exclude in $excludeFolders) {
        if ($folderName -like "*$exclude*") {
            return $true
        }
    }
    
    # Also check full path for OneDrive
    if ($FolderPath -like "*OneDrive*" -or $FolderPath -like "*Google Drive*" -or $FolderPath -like "*Dropbox*") {
        return $true
    }
    
    return $false
}

function Get-FilesQuick {
    param(
        [string]$Path,
        [string]$Filter,
        [int]$Depth = 0
    )
    
    if ($Depth -gt 3) { return @() }
    
    $files = @()
    
    try {
        $files += @(Get-ChildItem -Path $Path -Filter $Filter -File -Force -ErrorAction SilentlyContinue)
        
        if ($Depth -lt 3) {
            $dirs = @(Get-ChildItem -Path $Path -Directory -Force -ErrorAction SilentlyContinue)
            foreach ($dir in $dirs) {
                if (-not (Should-SkipFolder -FolderPath $dir.FullName)) {
                    $files += Get-FilesQuick -Path $dir.FullName -Filter $Filter -Depth ($Depth + 1)
                }
            }
        }
    }
    catch { }
    
    return $files
}

function Copy-UserFiles {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [string]$Filter,
        [string]$Category
    )
    
    if (-not (Test-Path -Path $SourcePath)) {
        return 0
    }
    
    $count = 0
    
    try {
        $files = @(Get-FilesQuick -Path $SourcePath -Filter $Filter)
        
        foreach ($file in $files) {
            try {
                $targetDir = Join-Path -Path $DestPath -ChildPath $Category
                
                if (-not (Test-Path -Path $targetDir)) {
                    New-Item -ItemType Directory -Path $targetDir -Force -ErrorAction Stop | Out-Null
                }
                
                $targetFile = Join-Path -Path $targetDir -ChildPath $file.Name
                Copy-Item -Path $file.FullName -Destination $targetFile -Force -ErrorAction Stop
                
                $script:copiedFiles += @{
                    Source = $file.FullName
                    Destination = $targetFile
                    Size = $file.Length
                    Category = $Category
                }
                
                $count++
            }
            catch {
                $script:failedFiles += $file.FullName
            }
        }
    }
    catch { }
    
    return $count
}

function Format-Duration {
    param([timespan]$Duration)
    
    $hours = [int]$Duration.TotalHours
    $minutes = $Duration.Minutes
    $seconds = $Duration.Seconds
    
    return "$($hours):$($minutes.ToString('00')):$($seconds.ToString('00'))"
}

function Main {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║     Disaster Recovery - File Gathering Script v2.4         ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "Note: Cloud storage folders (OneDrive, Google Drive, etc)" -ForegroundColor Yellow
    Write-Host "      will be skipped automatically." -ForegroundColor Yellow
    Write-Host ""
    
    # Get destination
    if ([string]::IsNullOrEmpty($DestinationPath)) {
        $DestinationPath = Get-DestinationPath
    }
    
    Write-Host ""
    Write-Host "Destination: $DestinationPath" -ForegroundColor Green
    Write-Host ""
    
    # Quick scan
    Write-Host "Scanning for files (this may take a minute)..." -ForegroundColor Yellow
    $scanStart = Get-Date
    $totalSize = 0
    $totalFiles = 0
    
    foreach ($searchPath in $searchPaths) {
        if (Test-Path -Path $searchPath) {
            $pathName = Split-Path -Path $searchPath -Leaf
            Write-Host "  Checking: $pathName" -ForegroundColor Cyan
            
            foreach ($category in $fileExtensions.Keys) {
                foreach ($ext in $fileExtensions[$category]) {
                    $files = @(Get-FilesQuick -Path $searchPath -Filter $ext)
                    $totalFiles += $files.Count
                    $totalSize += ($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                }
            }
        }
    }
    
    $scanTime = [math]::Round(((Get-Date) - $scanStart).TotalSeconds, 1)
    $sizeGB = [math]::Round($totalSize / 1GB, 2)
    
    Write-Host ""
    Write-Host "Found $totalFiles files ($sizeGB GB) in $scanTime seconds" -ForegroundColor Green
    Write-Host ""
    
    # Confirm
    Write-Host "Ready to backup $totalFiles files to:" -ForegroundColor Yellow
    Write-Host "  $DestinationPath" -ForegroundColor Cyan
    Write-Host ""
    $confirm = Read-Host "Continue? (Y/N)"
    
    if ($confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Host "Cancelled." -ForegroundColor Red
        exit
    }
    
    # Backup
    Write-Host ""
    Write-Host "Starting backup..." -ForegroundColor Green
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    
    $backupStart = Get-Date
    $totalCopied = 0
    
    foreach ($category in $fileExtensions.Keys) {
        Write-Host "[$category]" -ForegroundColor Green
        $catCount = 0
        
        foreach ($searchPath in $searchPaths) {
            if (Test-Path -Path $searchPath) {
                foreach ($ext in $fileExtensions[$category]) {
                    $copied = Copy-UserFiles -SourcePath $searchPath `
                                             -DestPath $DestinationPath `
                                             -Filter $ext `
                                             -Category $category
                    $catCount += $copied
                    $totalCopied += $copied
                }
            }
        }
        
        Write-Host "  Copied: $catCount files" -ForegroundColor Cyan
    }
    
    $backupDuration = (Get-Date) - $backupStart
    $formattedDuration = Format-Duration -Duration $backupDuration
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║           BACKUP COMPLETE                                  ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "Summary:" -ForegroundColor Green
    Write-Host "  Files Copied:  $totalCopied" -ForegroundColor Green
    Write-Host "  Failed:        $($script:failedFiles.Count)" -ForegroundColor $(if ($script:failedFiles.Count -eq 0) { 'Green' } else { 'Red' })
    Write-Host "  Duration:      $formattedDuration" -ForegroundColor Green
    Write-Host "  Destination:   $DestinationPath" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "Backup completed successfully!" -ForegroundColor Green
    Write-Host ""
}

Main