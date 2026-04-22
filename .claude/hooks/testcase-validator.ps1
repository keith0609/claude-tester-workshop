# testcase-validator.ps1 v8.2 — exit 0 + JSON voor PostToolUse

$LogFile = "$PSScriptRoot\validation.log"

if (-not (Test-Path (Split-Path $LogFile -Parent))) {
    New-Item -ItemType Directory -Force -Path (Split-Path $LogFile -Parent) | Out-Null
}

# Lees JSON input van stdin met native PowerShell
$JsonInput = [Console]::In.ReadToEnd()

$Event = $null

try {
    $Event = $JsonInput | ConvertFrom-Json
} catch {
    exit 0
}

$FilePath = $null

if ($Event -and $Event.tool_input -and $Event.tool_input.file_path) {
    $FilePath = $Event.tool_input.file_path
}

if (-not $FilePath) { exit 0 }

if ($FilePath -notmatch '\.feature$' -and $FilePath -notmatch 'testcases\.md$') { exit 0 }

if (-not (Test-Path $FilePath)) {
    "$(Get-Date -Format 'o') SKIP $FilePath" | Add-Content $LogFile
    exit 0
}

$Content = Get-Content $FilePath -Raw
$Issues = @()

if ($FilePath -match '\.feature$') {
    if ($Content -notmatch '(?m)^Feature:') { $Issues += "Missing 'Feature:' keyword" }
    if ($Content -notmatch 'Scenario:') { $Issues += "No Scenario found" }
    if ($Content -match 'Scenario:' -and $Content -notmatch '(?m)^\s*When ') { $Issues += "Scenario without 'When' step" }
    if ($Content -match 'Scenario:' -and $Content -notmatch '(?m)^\s*Then ') { $Issues += "Scenario without 'Then' step" }
}

if ($Issues.Count -eq 0) {
    "$(Get-Date -Format 'o') OK $FilePath" | Add-Content $LogFile
    exit 0
}

# Issues gevonden: bouw JSON en stuur naar stdout
$IssueLines = ($Issues | ForEach-Object { " - $_" }) -join "`n"
$FileName = Split-Path $FilePath -Leaf

"$(Get-Date -Format 'o') ISSUES ${FilePath}: $($Issues -join '; ')" | Add-Content $LogFile

$payload = @{
    decision = "block"
    reason = "Gherkin validatie mislukt in $FileName"
    hookSpecificOutput = @{
        hookEventName = "PostToolUse"
        additionalContext = "Validatieproblemen in ${FileName}:`n${IssueLines}`n`nCorrigeer zodat elk Scenario een Feature:, When en Then heeft."
    }
} | ConvertTo-Json -Depth 4 -Compress

Write-Output $payload

# exit 0 + JSON = de officiële gestructureerde feedback-route voor PostToolUse
exit 0