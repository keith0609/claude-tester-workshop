#!/usr/bin/env bash
# workshop-smoke-test.sh v8.2
# Controleert pre-conditions voor workshop "Claude voor Senior Testers v8.2"
# Locatie: workshop-assets repo root

set -u

PASS=0
FAIL=0
WARN=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; PASS=$((PASS+1)); }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; FAIL=$((FAIL+1)); }
warn() { echo -e "  ${YELLOW}[WARN]${NC} $1"; WARN=$((WARN+1)); }
info() { echo -e "  ${BLUE}[INFO]${NC} $1"; }
section() { echo -e "\n${BOLD}== $1 ==${NC}"; }

echo ""
echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD}  Workshop Smoke Test v8.2 - Claude voor Senior Testers${NC}"
echo -e "${BOLD}  $(date '+%Y-%m-%d %H:%M')${NC}"
echo -e "${BOLD}======================================================${NC}"

section "1. Claude Code"

if command -v claude &>/dev/null; then
    VERSION=$(claude --version 2>/dev/null | head -1)
    ok "claude gevonden: $VERSION"
else
    fail "claude niet gevonden"
    info "  Installeer: curl -fsSL https://claude.ai/install.sh | bash"
fi

if command -v claude &>/dev/null; then
    if claude auth status --text >/tmp/claude-auth.txt 2>&1; then
        if grep -qiE "signed in|logged in|authenticated" /tmp/claude-auth.txt; then
            ok "claude auth status: ingelogd"
        else
            warn "claude auth status werkt, maar niet ingelogd — start 'claude' en log in"
        fi
    else
        warn "claude auth status niet gelukt — commando naam kan per versie variëren"
    fi
fi

if command -v claude &>/dev/null; then
    DOCTOR=$(claude doctor 2>&1 | head -20)
    if echo "$DOCTOR" | grep -qi "no issues\|all checks passed"; then
        ok "claude doctor: geen kritieke issues"
    elif echo "$DOCTOR" | grep -qi "error\|fail\|critical"; then
        fail "claude doctor: issues gevonden"
    else
        warn "claude doctor: output onduidelijk"
    fi
fi

section "2. Python & packages"

PYTHON_BIN=""
if command -v python3 &>/dev/null; then
    PYTHON_BIN="python3"
elif command -v python &>/dev/null; then
    PYTHON_BIN="python"
fi

if [[ -n "$PYTHON_BIN" ]]; then
    PY_VERSION=$($PYTHON_BIN --version 2>&1)
    PY_MINOR=$($PYTHON_BIN -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo "0")
    if [[ $PY_MINOR -ge 10 ]]; then
        ok "Python: $PY_VERSION"
    else
        warn "Python < 3.10: $PY_VERSION"
    fi
    for pkg in anthropic frontmatter yaml; do
        if $PYTHON_BIN -c "import $pkg" 2>/dev/null; then
            ok "python package: $pkg"
        else
            fail "python package ontbreekt: $pkg"
        fi
    done
else
    fail "geen Python gevonden"
fi

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    KEY_PREFIX="${ANTHROPIC_API_KEY:0:8}"
    ok "ANTHROPIC_API_KEY gezet (${KEY_PREFIX}...)"
else
    warn "ANTHROPIC_API_KEY niet gezet"
    info "  Pro/Max subscribers: via claude ingelogd — key niet nodig"
    info "  Blok 5 pipeline-script: key WEL nodig"
fi

section "3. Project-level assets"

if [[ -f ".claude/settings.json" ]]; then
    ok ".claude/settings.json aanwezig"
    if [[ -n "$PYTHON_BIN" ]]; then
        if $PYTHON_BIN -c "import json; json.load(open('.claude/settings.json'))" 2>/dev/null; then
            ok ".claude/settings.json is geldige JSON"
        else
            fail ".claude/settings.json heeft JSON-fout"
        fi
    fi
else
    warn ".claude/settings.json ontbreekt"
fi

if [[ -f ".mcp.json" ]]; then
    ok ".mcp.json aanwezig"
else
    warn ".mcp.json ontbreekt"
fi

if [[ -n "${ADO_ORG:-}" ]]; then
    ok "ADO_ORG env var: $ADO_ORG"
else
    warn "ADO_ORG env var niet gezet"
fi

section "4. Subagent"

PROJECT_AGENT=".claude/agents/regression-risk-analyst.md"
USER_AGENT="${HOME}/.claude/agents/regression-risk-analyst.md"

FOUND_AGENT=""
if [[ -f "$PROJECT_AGENT" ]]; then
    ok "Subagent project-level: $PROJECT_AGENT"
    FOUND_AGENT="$PROJECT_AGENT"
elif [[ -f "$USER_AGENT" ]]; then
    warn "Subagent alleen user-level"
    FOUND_AGENT="$USER_AGENT"
else
    fail "Subagent NIET gevonden"
fi

if [[ -n "$FOUND_AGENT" && -n "$PYTHON_BIN" ]]; then
    FM_CHECK=$($PYTHON_BIN - <<PY 2>&1
from pathlib import Path
import re, sys
try: import yaml
except ImportError: sys.exit("pyyaml ontbreekt")
text = Path("$FOUND_AGENT").read_text(encoding="utf-8")
m = re.match(r'^---\n(.*?)\n---\n', text, re.S)
if not m: sys.exit("geen frontmatter")
yaml.safe_load(m.group(1))
print("OK")
PY
)
    if [[ "$FM_CHECK" == "OK" ]]; then
        ok "Subagent frontmatter geldig"
    else
        fail "Frontmatter ongeldig: $FM_CHECK"
    fi
fi

if command -v claude &>/dev/null; then
    if claude agents >/tmp/claude-agents.txt 2>&1; then
        if grep -qi "regression-risk-analyst" /tmp/claude-agents.txt; then
            ok "claude agents toont regression-risk-analyst"
        else
            warn "claude agents werkt, subagent niet in output"
        fi
    else
        warn "claude agents CLI niet beschikbaar"
    fi
fi

section "5. Hook (bonus)"

if [[ -f ".claude/hooks/testcase-validator.sh" ]]; then
    ok "Bash hook aanwezig"
    [[ -x ".claude/hooks/testcase-validator.sh" ]] && ok "Bash hook uitvoerbaar" || warn "chmod +x nodig"
elif [[ -f ".claude/hooks/testcase-validator.ps1" ]]; then
    ok "PowerShell hook aanwezig"
else
    warn "Hook ontbreekt (bonus)"
fi

section "6. MCP"

if command -v claude &>/dev/null; then
    MCP_LIST=$(claude mcp list 2>/dev/null || echo "")
    if echo "$MCP_LIST" | grep -qi "azure\|devops"; then
        ok "Azure DevOps MCP zichtbaar"
    else
        warn "Azure DevOps MCP niet zichtbaar"
    fi
fi

section "7. Pipeline"

if [[ -f "pipeline-exercise/md-to-gherkin-with-model-choice.py" ]]; then
    ok "Pipeline script aanwezig"
    if [[ -n "$PYTHON_BIN" ]] && $PYTHON_BIN -m py_compile pipeline-exercise/md-to-gherkin-with-model-choice.py 2>/dev/null; then
        ok "Pipeline script compileert"
    else
        warn "Pipeline script compileert niet"
    fi
else
    warn "Pipeline script ontbreekt"
fi

section "8. Assets"

for f in "jira-ticket-STORE-1234.md" "fallback-skills/testcase-generator/SKILL.md" "subagent-templates/regression-risk-analyst.md"; do
    if [[ -f "$f" ]]; then
        ok "Aanwezig: $f"
    else
        warn "Ontbreekt: $f"
    fi
done

echo ""
echo -e "${BOLD}== Samenvatting ==${NC}"
echo -e "  ${GREEN}PASS:${NC} $PASS    ${YELLOW}WARN:${NC} $WARN    ${RED}FAIL:${NC} $FAIL"
echo ""
echo -e "${BOLD}== HANDMATIGE CHECKS ==${NC}"
echo ""
echo "Start 'claude' en run in de REPL:"
echo "  /status    (login + plan)"
echo "  /usage     (subscription usage)"
echo "  /cost      (API token kosten)"
echo "  /stats     (subscriber usage patterns)"
echo "  /agents    (subagents zichtbaar?)"
echo "  /mcp       (MCP servers zichtbaar?)"
echo "  /exit"
echo ""
echo "Check op claude.ai: Settings -> Connectors -> GitHub"
echo ""

[[ $FAIL -eq 0 ]] && exit 0 || exit 1
