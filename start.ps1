# Steam Workshop Uploader — quick launch
$ErrorActionPreference = "Stop"
$ProjectRoot = $PSScriptRoot
Set-Location -LiteralPath $ProjectRoot

$ExportedExe = Join-Path $ProjectRoot "export\windows\Steam Workshop Uploader.exe"
$GodotExe = Join-Path $ProjectRoot "Godot_v4.6.2\Godot_v4.6.2-stable_win64.exe"

if (Test-Path -LiteralPath $ExportedExe) {
    Write-Host "Starting Steam Workshop Uploader..."
    Start-Process -LiteralPath $ExportedExe -WorkingDirectory (Split-Path -LiteralPath $ExportedExe)
    exit 0
}

if (-not (Test-Path -LiteralPath $GodotExe)) {
    Write-Error @"
Godot not found: $GodotExe

Place Godot 4.6 in Godot_v4.6.2\ or export the project to:
  export\windows\Steam Workshop Uploader.exe
"@
}

Write-Host "Starting Steam Workshop Uploader (Godot)..."
& $GodotExe --path $ProjectRoot
exit $LASTEXITCODE
