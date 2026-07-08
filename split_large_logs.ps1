param(
    [Parameter(Mandatory = $true)]
    [string]$Root,

    [Parameter(Mandatory = $true)]
    [int64]$MaxBytes
)

$ErrorActionPreference = "Stop"

$encoding = New-Object System.Text.UTF8Encoding($false)
$newLine = [Environment]::NewLine

$files = Get-ChildItem -Path $Root -Recurse -File | Where-Object {
    $_.Length -gt $MaxBytes -and $_.Name -notmatch "\.part\d{4}\."
}

foreach ($file in $files) {
    Write-Host "Splitting large file: $($file.FullName) size=$($file.Length)"

    $existingPartsPattern = "{0}.part*{1}" -f $file.BaseName, $file.Extension
    Get-ChildItem -Path $file.DirectoryName -File -Filter $existingPartsPattern | Remove-Item -Force

    $reader = [System.IO.StreamReader]::new($file.FullName, $encoding)
    $index = 1
    $currentBytes = 0
    $writer = $null
    $parts = New-Object System.Collections.Generic.List[string]

    try {
        $partPath = Join-Path $file.DirectoryName ("{0}.part{1:D4}{2}" -f $file.BaseName, $index, $file.Extension)
        $parts.Add($partPath)
        $writer = [System.IO.StreamWriter]::new($partPath, $false, $encoding)

        while (($line = $reader.ReadLine()) -ne $null) {
            $lineWithNewLine = $line + $newLine
            $lineBytes = $encoding.GetByteCount($lineWithNewLine)

            if ($lineBytes -gt $MaxBytes) {
                throw "Cannot split safely: one single line is bigger than MaxBytes in $($file.FullName)"
            }

            if ($currentBytes -gt 0 -and ($currentBytes + $lineBytes) -gt $MaxBytes) {
                $writer.Close()

                $index++
                $currentBytes = 0

                $partPath = Join-Path $file.DirectoryName ("{0}.part{1:D4}{2}" -f $file.BaseName, $index, $file.Extension)
                $parts.Add($partPath)
                $writer = [System.IO.StreamWriter]::new($partPath, $false, $encoding)
            }

            $writer.Write($lineWithNewLine)
            $currentBytes += $lineBytes
        }
    }
    finally {
        if ($writer -ne $null) {
            $writer.Close()
        }

        if ($reader -ne $null) {
            $reader.Close()
        }
    }

    $oversizedParts = @(
        $parts | Where-Object {
            (Get-Item $_).Length -gt $MaxBytes
        }
    )

    if ($oversizedParts.Count -gt 0) {
        Write-Host "Oversized parts detected:"
        foreach ($part in $oversizedParts) {
            $partItem = Get-Item $part
            Write-Host "$($partItem.FullName) size=$($partItem.Length)"
        }

        throw "Split failed: at least one part is still too large for $($file.FullName)"
    }

    Remove-Item $file.FullName

    Write-Host "Original removed after split: $($file.FullName)"

    foreach ($part in $parts) {
        $partItem = Get-Item $part
        Write-Host "Created part: $($partItem.FullName) size=$($partItem.Length)"
    }
}
