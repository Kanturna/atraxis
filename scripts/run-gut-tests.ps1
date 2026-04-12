param(
	[string]$GodotConsolePath = "D:\Programme\Godot\godot_console.exe",
	[string[]]$TestDirs = @("res://tests"),
	[string[]]$Tests = @(),
	[string]$Select = ""
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$appDataRoot = Join-Path $repoRoot ".test_env\appdata"
$localAppDataRoot = Join-Path $repoRoot ".test_env\localappdata"
$runnerScript = "res://addons/gut/gut_cmdln.gd"
$godotArgs = @(
	"--headless",
	"--path", $repoRoot,
	"-s", $runnerScript,
	"-gexit"
)

if (-not (Test-Path -LiteralPath $GodotConsolePath)) {
	throw "Godot console executable not found: $GodotConsolePath"
}

New-Item -ItemType Directory -Force -Path $appDataRoot | Out-Null
New-Item -ItemType Directory -Force -Path $localAppDataRoot | Out-Null

foreach ($dir in $TestDirs) {
	$godotArgs += "-gdir=$dir"
}

foreach ($test in $Tests) {
	$godotArgs += "-gtest=$test"
}

if ($Select) {
	$godotArgs += "-gselect=$Select"
}

$previousAppData = $env:APPDATA
$previousLocalAppData = $env:LOCALAPPDATA
$exitCode = 1

Push-Location $repoRoot

try {
	$env:APPDATA = $appDataRoot
	$env:LOCALAPPDATA = $localAppDataRoot

	Write-Host "Running GUT with $GodotConsolePath"
	Write-Host "APPDATA=$appDataRoot"
	Write-Host "LOCALAPPDATA=$localAppDataRoot"

	& $GodotConsolePath @godotArgs
	$exitCode = $LASTEXITCODE
}
finally {
	Pop-Location

	if ($null -ne $previousAppData) {
		$env:APPDATA = $previousAppData
	}
	else {
		Remove-Item Env:APPDATA -ErrorAction SilentlyContinue
	}

	if ($null -ne $previousLocalAppData) {
		$env:LOCALAPPDATA = $previousLocalAppData
	}
	else {
		Remove-Item Env:LOCALAPPDATA -ErrorAction SilentlyContinue
	}
}

exit $exitCode
