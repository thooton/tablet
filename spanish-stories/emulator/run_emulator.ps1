# Runs the app in the desktop emulator (creates a Python venv with PySide6 on
# first use). Extra arguments go to emulator.py, e.g. --fresh, or use --test
# to run the automated test instead.
$ErrorActionPreference = "Stop"
$venv = if ($env:SPANISH_READER_VENV) { $env:SPANISH_READER_VENV } else { Join-Path $env:LOCALAPPDATA "spanish-reader-venv" }
$py = Join-Path $venv "Scripts\python.exe"

if (-not (Test-Path $py)) {
    Write-Host "Creating Python environment in $venv (one time) ..."
    python -m venv $venv
    & $py -m pip install --quiet "PySide6>=6.5"
}

if ($args.Count -gt 0 -and $args[0] -eq "--test") {
    $rest = @($args | Select-Object -Skip 1)
    & $py (Join-Path $PSScriptRoot "test_app.py") @rest
} else {
    & $py (Join-Path $PSScriptRoot "emulator.py") @args
}
exit $LASTEXITCODE
