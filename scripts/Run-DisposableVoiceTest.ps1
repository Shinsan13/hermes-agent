[CmdletBinding()]
param(
    [string]$ModelBaseUrl = 'http://127.0.0.1:18193/v1',
    [string]$Model = 'corbin2-bonsai27b',
    [switch]$Preflight,
    [switch]$KeepHome
)

$ErrorActionPreference = 'Stop'
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$python = 'C:\Users\chris\AppData\Local\hermes\hermes-agent\venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) {
    throw "Hermes v0.21.5 Python was not found at $python. This launcher never installs or repairs Hermes."
}

if (-not ($ModelBaseUrl -match '^http://127\.0\.0\.1(?::\d+)?/v1/?$')) {
    throw 'ModelBaseUrl must be a loopback OpenAI-compatible /v1 endpoint.'
}

try {
    $models = Invoke-RestMethod -Uri ($ModelBaseUrl.TrimEnd('/') + '/models') -Method Get -TimeoutSec 5
}
catch {
    throw "Local model endpoint preflight failed: $($_.Exception.Message). The launcher did not start or change it."
}

$modelIds = @($models.data | ForEach-Object { [string]$_.id })
if ($modelIds -notcontains $Model) {
    throw "Configured model '$Model' is not listed by the local endpoint. Available: $($modelIds -join ', ')"
}

$testHome = Join-Path ([System.IO.Path]::GetTempPath()) ('hermes-c2-062-voice-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testHome -Force | Out-Null
$config = @"
model:
  provider: openai
  model: $Model
  base_url: $ModelBaseUrl
  api_key: local-disposable-only
  api_mode: chat_completions
voice:
  silence_duration: 1.0
  max_recording_seconds: 30.0
display:
  interface: tui
"@
Set-Content -LiteralPath (Join-Path $testHome 'config.yaml') -Value $config -Encoding UTF8

$oldHome = $env:HERMES_HOME
$oldVoice = $env:HERMES_VOICE
$oldTts = $env:HERMES_VOICE_TTS
$pushed = $false
try {
    $env:HERMES_HOME = $testHome
    $env:HERMES_VOICE = '1'
    $env:HERMES_VOICE_TTS = '1'
    Push-Location $repoRoot
    $pushed = $true
    & $python -m hermes_cli.main --version
    if ($LASTEXITCODE -ne 0) {
        throw "Patched Hermes version preflight failed with exit code $LASTEXITCODE."
    }
    if ($Preflight) {
        Write-Output "DISPOSABLE_VOICE_PREFLIGHT_OK home=$testHome model=$Model"
        return
    }
    Write-Host ''
    Write-Host 'Disposable C2-062 hardware checklist (nothing here changes installed Hermes or CORBIN):'
    Write-Host '1. Say an English sentence, then a Romanian sentence; each should submit after about one second of silence.'
    Write-Host '2. Confirm the reply is spoken and listening resumes automatically.'
    Write-Host '3. Press F8 while listening, verify PAUSED and microphone release; press F8 again to resume.'
    Write-Host '4. Type a normal chat message and press Enter; verify the same local model answers.'
    Write-Host '5. Test stop and a spoken interruption during TTS; then exit normally.'
    Write-Host ''
    & $python -m hermes_cli.main --tui
    if ($LASTEXITCODE -ne 0) {
        throw "Disposable Hermes TUI exited with code $LASTEXITCODE."
    }
}
finally {
    if ($pushed) {
        Pop-Location
    }
    $env:HERMES_HOME = $oldHome
    $env:HERMES_VOICE = $oldVoice
    $env:HERMES_VOICE_TTS = $oldTts
    if ($KeepHome) {
        Write-Output "DISPOSABLE_VOICE_HOME_PRESERVED=$testHome"
    }
    else {
        Remove-Item -LiteralPath $testHome -Recurse -Force -ErrorAction SilentlyContinue
    }
}
