param(
    [Parameter(Mandatory = $true)]
    [string]$Source,

    [Parameter(Mandatory = $true)]
    [string]$Destination
)

$ErrorActionPreference = "Stop"

function Copy-ActiveFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    $sourceStream = $null
    $destinationStream = $null

    try {
        $sourceStream = [System.IO.File]::Open(
            $SourcePath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
        )

        $destinationDirectory = Split-Path -Parent $DestinationPath
        if (-not (Test-Path $destinationDirectory)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        $destinationStream = [System.IO.File]::Open(
            $DestinationPath,
            [System.IO.FileMode]::Create,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Read
        )

        $sourceStream.CopyTo($destinationStream, 1048576)
    }
    finally {
        if ($destinationStream -ne $null) {
            $destinationStream.Close()
        }

        if ($sourceStream -ne $null) {
            $sourceStream.Close()
        }
    }

    $sourceItem = Get-Item $SourcePath
    [System.IO.File]::SetLastWriteTime($DestinationPath, $sourceItem.LastWriteTime)
}

if (-not (Test-Path $Source)) {
    throw "Source does not exist: $Source"
}

if (-not (Test-Path $Destination)) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
}

$pathSeparators = [char[]]@(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
)

$sourceRoot = (Resolve-Path $Source).Path.TrimEnd($pathSeparators)
$destinationRoot = (Resolve-Path $Destination).Path.TrimEnd($pathSeparators)

Get-ChildItem -Path $sourceRoot -File -Recurse | ForEach-Object {
    $relativePath = $_.FullName.Substring($sourceRoot.Length).TrimStart($pathSeparators)
    $destinationPath = Join-Path $destinationRoot $relativePath

    try {
        Write-Host "Copying active log snapshot: $($_.FullName) -> $destinationPath"
        Copy-ActiveFile -SourcePath $_.FullName -DestinationPath $destinationPath
    }
    catch {
        Write-Warning "Failed to copy active log snapshot: $($_.FullName) | error=$($_.Exception.Message)"
    }
}
