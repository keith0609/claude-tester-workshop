# workshop-smoke-test.ps1 v8.2.1
# Controleert pre-conditions voor workshop Claude voor Senior Testers
# Gebruik: .\workshop-smoke-test.ps1
# Locatie: workshop-assets repo root

$Pass = 0
$Fail = 0
$Warn = 0

function Write-Ok {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
    $script:Pass++
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [FAIL] $Message" -ForegroundColor Red
    $script:Fail++
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [WARN] $Message" -ForegroundColor Yellow
    $script:Warn++
}

function Write-Info {
    param([string]$Message)
    Write-Host "  [INFO] $Message" -ForegroundColor Cyan
}

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "== $Title ==" -ForegroundColor White
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor White
Write-Host "  Workshop Smoke Test v8.2 - Claude voor Senior Testers"   -ForegroundColor White
Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm')"                   -ForegroundColor Gray
Write-Host "==========================================================" -ForegroundColor White

# ── 1. CLAUDE CODE ──────────────────────────────────────────────────────────────
Write-Section "1. Claude Code"

$ClaudeCmd = Get-Command claude -ErrorAction SilentlyContinue
if ($ClaudeCmd) {
    $Version = & claude --version 2>$null | Select-Object -First 1
    Write-Ok "claude gevonden: $Version"
} else {
    Write-Fail "claude niet gevonden"
    Write-Info "Installeer: irm https://claude.ai/install.ps1 | iex"
    Write-Info "Daarna PowerShell sluiten en opnieuw openen"
}

if ($ClaudeCmd) {
    try {
        $AuthOutput = & claude auth status --text 2>&1 | Out-String
        if ($AuthOutput -match "signed in|logged in|authenticated") {
            Write-Ok "claude auth status: ingelogd"
        } else {
            Write-Warn "claude auth status werkt, maar niet ingelogd"
            Write-Info "Start 'claude' en log in via browser"
        }
    } catch {
        Write-Warn "claude auth status niet gelukt (commando kan per versie varieren)"
    }

    try {
        $DoctorOutput = & claude doctor 2>&1 | Out-String
        if ($DoctorOutput -match "no issues|all checks passed") {
            Write-Ok "claude doctor: geen kritieke issues"
        } elseif ($DoctorOutput -match "error|fail|critical") {
            Write-Fail "claude doctor: issues gevonden"
        } else {
            Write-Warn "claude doctor: output onduidelijk"
        }
    } catch {
        Write-Warn "claude doctor niet gelukt"
    }
}

# ── 2. PYTHON ───────────────────────────────────────────────────────────────────
Write-Section "2. Python en packages"

$Python = Get-Command python -ErrorAction SilentlyContinue
if (-not $Python) {
    $Python = Get-Command python3 -ErrorAction SilentlyContinue
}

if ($Python) {
    $PyVersion = & $Python.Name --version 2>&1 | Out-String
    $PyMinor = & $Python.Name -c "import sys; print(sys.version_info.minor)" 2>$null
    if ([int]$PyMinor -ge 10) {
        Write-Ok "Python: $($PyVersion.Trim())"
    } else {
        Write-Warn "Python versie is lager dan 3.10 (gevonden: $($PyVersion.Trim()))"
    }

    foreach ($pkg in @("anthropic", "frontmatter", "yaml")) {
        $result = & $Python.Name -c "import $pkg; print('ok')" 2>$null
        if ($result -eq "ok") {
            Write-Ok "python package: $pkg"
        } else {
            Write-Fail "python package ontbreekt: $pkg"
            Write-Info "Installeer: $($Python.Name) -m pip install --user anthropic python-frontmatter pyyaml"
        }
    }
} else {
    Write-Fail "Python niet gevonden"
    Write-Info "Download van python.org/downloads (vink 'Add Python to PATH' aan)"
}

# API key
$ApiKey = [System.Environment]::GetEnvironmentVariable("ANTHROPIC_API_KEY")
if ($ApiKey) {
    $KeyPrefix = $ApiKey.Substring(0, [Math]::Min(8, $ApiKey.Length))
    $KeyMsg = "ANTHROPIC_API_KEY gezet (" + $KeyPrefix + "...)"
    Write-Ok $KeyMsg
    Write-Info "Nodig voor pipeline-oefening Blok 5 Python-script"
} else {
    Write-Warn "ANTHROPIC_API_KEY niet gezet"
    Write-Info "Pro/Max/Team/Enterprise: via claude subscriptie - key niet nodig"
    Write-Info "Blok 5 pipeline: key WEL nodig"
    Write-Info "Instellen via: [Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY','YOUR_ANTHROPIC_API_KEY_HERE','User')"
}

# ── 3. PROJECT-LEVEL ASSETS ─────────────────────────────────────────────────────
Write-Section "3. Project-level assets"

if (Test-Path ".claude\settings.json") {
    Write-Ok ".claude\settings.json aanwezig"
    if ($Python) {
        $jsonCheck = & $Python.Name -c "import json; json.load(open('.claude/settings.json')); print('ok')" 2>$null
        if ($jsonCheck -eq "ok") {
            Write-Ok ".claude\settings.json is geldige JSON"
        } else {
            Write-Fail ".claude\settings.json heeft JSON-fout"
        }
    }
} else {
    Write-Warn ".claude\settings.json ontbreekt (hook-registratie)"
}

if (Test-Path ".mcp.json") {
    Write-Ok ".mcp.json aanwezig"
    if ($Python) {
        $jsonCheck = & $Python.Name -c "import json; json.load(open('.mcp.json')); print('ok')" 2>$null
        if ($jsonCheck -eq "ok") {
            Write-Ok ".mcp.json is geldige JSON"
        } else {
            Write-Fail ".mcp.json heeft JSON-fout"
        }
    }
} else {
    Write-Warn ".mcp.json ontbreekt (Azure DevOps MCP config)"
}

$AdoOrg = [System.Environment]::GetEnvironmentVariable("ADO_ORG")
if ($AdoOrg) {
    Write-Ok "ADO_ORG env var: $AdoOrg"
} else {
    Write-Warn "ADO_ORG env var niet gezet"
    Write-Info "[Environment]::SetEnvironmentVariable('ADO_ORG','https://dev.azure.com/jouw-org','User')"
}

# ── 4. SUBAGENT ─────────────────────────────────────────────────────────────────
Write-Section "4. Subagent"

$ProjectAgent = ".claude\agents\regression-risk-analyst.md"
$UserAgent    = "$HOME\.claude\agents\regression-risk-analyst.md"

$FoundAgent = $null
if (Test-Path $ProjectAgent) {
    Write-Ok "Subagent project-level: $ProjectAgent"
    $FoundAgent = $ProjectAgent
} elseif (Test-Path $UserAgent) {
    Write-Warn "Subagent alleen user-level: $UserAgent"
    Write-Info "Verplaats naar .claude\agents\ voor team-deelbaarheid"
    $FoundAgent = $UserAgent
} else {
    Write-Fail "Subagent NIET gevonden"
    Write-Info "New-Item -ItemType Directory -Force -Path '.claude\agents'"
    Write-Info "Copy-Item subagent-templates\regression-risk-analyst.md .claude\agents\"
}

if ($FoundAgent -and $Python) {
    $TempScript = [System.IO.Path]::GetTempFileName() + ".py"
    $FmScriptContent = @"
from pathlib import Path
import re, sys
try:
    import yaml
except ImportError:
    sys.exit('pyyaml ontbreekt')
text = Path(r'$FoundAgent').read_text(encoding='utf-8')
m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
if not m:
    sys.exit('geen frontmatter')
yaml.safe_load(m.group(1))
print('OK')
"@
    Set-Content -Path $TempScript -Value $FmScriptContent -Encoding UTF8
    try {
        $FmResult = & $Python.Name $TempScript 2>&1 | Out-String
        if ($FmResult.Trim() -eq "OK") {
            Write-Ok "Subagent frontmatter geldig"
        } else {
            Write-Fail "Subagent frontmatter ongeldig: $($FmResult.Trim())"
        }
    } finally {
        Remove-Item $TempScript -ErrorAction SilentlyContinue
    }
}

if ($ClaudeCmd) {
    try {
        $AgentsOut = & claude agents 2>&1 | Out-String
        if ($AgentsOut -match "regression-risk-analyst") {
            Write-Ok "claude agents toont regression-risk-analyst"
        } else {
            Write-Warn "claude agents werkt, subagent niet in output"
        }
    } catch {
        Write-Warn "claude agents CLI niet beschikbaar (kan per versie varieren)"
    }
}

# ── 5. HOOK ─────────────────────────────────────────────────────────────────────
Write-Section "5. Hook (bonus)"

if (Test-Path ".claude\hooks\testcase-validator.ps1") {
    Write-Ok "PowerShell hook aanwezig: .claude\hooks\testcase-validator.ps1"
} elseif (Test-Path ".claude\hooks\testcase-validator.sh") {
    Write-Ok "Bash hook aanwezig (heb je Git Bash?)"
} else {
    Write-Warn "Hook ontbreekt (bonus, niet verplicht)"
}

# ── 6. MCP ──────────────────────────────────────────────────────────────────────
Write-Section "6. MCP servers"

if ($ClaudeCmd) {
    try {
        $McpList = & claude mcp list 2>$null | Out-String
        if ($McpList -match "azure|devops") {
            Write-Ok "Azure DevOps MCP zichtbaar"
        } else {
            Write-Warn "Azure DevOps MCP niet zichtbaar in claude mcp list"
            Write-Info "Controleer .mcp.json en ADO_ORG env var"
        }
    } catch {
        Write-Warn "claude mcp list niet gelukt"
    }
}

# ── 7. PIPELINE ─────────────────────────────────────────────────────────────────
Write-Section "7. Pipeline script"

if (Test-Path "pipeline-exercise\md-to-gherkin-with-model-choice.py") {
    Write-Ok "Pipeline script aanwezig"
    if ($Python) {
        try {
            & $Python.Name -m py_compile "pipeline-exercise\md-to-gherkin-with-model-choice.py" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Ok "Pipeline script compileert"
            } else {
                Write-Warn "Pipeline script compileert niet"
            }
        } catch {
            Write-Warn "Pipeline script compileert niet"
        }
    }
} else {
    Write-Warn "Pipeline script ontbreekt"
}

if (Test-Path "pipeline-exercise\testcases.md") {
    Write-Ok "Pipeline input aanwezig"
} else {
    Write-Warn "pipeline-exercise\testcases.md ontbreekt"
}

# ── 8. ASSETS ───────────────────────────────────────────────────────────────────
Write-Section "8. Workshop assets"

$Required = @(
    "jira-ticket-STORE-1234.md",
    "fallback-skills\testcase-generator\SKILL.md",
    "subagent-templates\regression-risk-analyst.md",
    "hook-templates\testcase-validator.ps1"
)

foreach ($f in $Required) {
    if (Test-Path $f) {
        Write-Ok "Aanwezig: $f"
    } else {
        Write-Warn "Ontbreekt: $f"
    }
}

# ── SAMENVATTING ────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "== Samenvatting ==" -ForegroundColor White
Write-Host "  PASS: $Pass    WARN: $Warn    FAIL: $Fail"
Write-Host ""

Write-Host "== HANDMATIGE CHECKS ==" -ForegroundColor White
Write-Host ""
Write-Host "Start Claude Code en run deze slash commands in de REPL:"
Write-Host ""
Write-Host "  1. claude                   (start REPL)"     -ForegroundColor Cyan
Write-Host "  2. /status                  (login en plan)"  -ForegroundColor Cyan
Write-Host "  3. /usage                   (subscription)"   -ForegroundColor Cyan
Write-Host "  4. /cost                    (tokenkosten)"    -ForegroundColor Cyan
Write-Host "  5. /stats                   (usage patterns)" -ForegroundColor Cyan
Write-Host "  6. /agents                  (subagents)"      -ForegroundColor Cyan
Write-Host "  7. /mcp                     (MCP servers)"    -ForegroundColor Cyan
Write-Host "  8. /exit"                                      -ForegroundColor Cyan
Write-Host ""
Write-Host "Daarna: claude.ai -> Settings -> Connectors -> GitHub check"
Write-Host ""

if ($Fail -eq 0 -and $Warn -eq 0) {
    Write-Host "Alles groen - klaar voor workshop." -ForegroundColor Green
    exit 0
} elseif ($Fail -eq 0) {
    Write-Host "Waarschuwingen aanwezig - kijk ze na voor workshop." -ForegroundColor Yellow
    exit 0
} else {
    Write-Host "Fouten gevonden - los op voor workshop." -ForegroundColor Red
    exit 1
}