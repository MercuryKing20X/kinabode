# PowerShell 5.1+ / PowerShell 7, no Bash or symlink privileges required.
# Examples:
#   $env:HABITAT_GODOT = 'C:\Tools\Godot\Godot.exe'
#   ./scripts/test-godot.ps1
#   ./scripts/test-godot.ps1 -Script test_foundation.gd,test_slice.gd
param([string[]]$Script = @('test_foundation.gd','test_slice.gd','test_work_orders.gd','test_farms.gd','test_barbecue_v4.gd'))
$ErrorActionPreference = 'Stop'
$runner = Join-Path $PSScriptRoot 'portable_godot_checks.py'
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) { $python = Get-Command python3 -ErrorAction Stop }
$arguments = @($runner)
foreach ($name in $Script) { $arguments += @('--script', $name) }
& $python.Source @arguments
exit $LASTEXITCODE
