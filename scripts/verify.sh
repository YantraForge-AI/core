#!/usr/bin/env bash
set -euo pipefail

# YantraForge verify.sh — Health check against running Paperclip instance
# Usage: ./scripts/verify.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PAPERCLIP_URL="${PAPERCLIP_URL:-http://localhost:3100}"
API="$PAPERCLIP_URL/api"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()    { echo -e "  ${GREEN}✓${NC} $1"; }
fail_item() { echo -e "  ${RED}✗${NC} $1"; FAILURES=$((FAILURES + 1)); }
warn_item() { echo -e "  ${YELLOW}!${NC} $1"; WARNINGS=$((WARNINGS + 1)); }
info()  { echo -e "${BLUE}[info]${NC}  $1"; }

FAILURES=0
WARNINGS=0

echo ""
echo "YantraForge Health Check"
echo "════════════════════════"
echo ""

# ─────────────────────────────────────────────
# 1. Paperclip server
# ─────────────────────────────────────────────

info "Paperclip Server"

if curl -sf "$API/health" &>/dev/null; then
    ok "Paperclip running at $PAPERCLIP_URL"
else
    fail_item "Paperclip not reachable at $PAPERCLIP_URL"
    echo ""
    echo "  Cannot continue without Paperclip. Start it with:"
    echo "    npx paperclipai run"
    echo ""
    exit 1
fi

echo ""

# ─────────────────────────────────────────────
# 2. Company and agents
# ─────────────────────────────────────────────

info "Company & Agents"

COMPANIES=$(curl -sf "$API/companies" 2>/dev/null || echo "[]")
COMPANY_COUNT=$(echo "$COMPANIES" | jq 'length')

if [ "$COMPANY_COUNT" -eq 0 ]; then
    fail_item "No companies found. Run ./scripts/init.sh first."
else
    COMPANY_NAME=$(echo "$COMPANIES" | jq -r '.[0].name')
    COMPANY_ID=$(echo "$COMPANIES" | jq -r '.[0].id')
    ok "Company: $COMPANY_NAME (id: $COMPANY_ID)"

    # Check agents
    AGENTS=$(curl -sf "$API/companies/$COMPANY_ID/agents" 2>/dev/null || echo "[]")
    AGENT_COUNT=$(echo "$AGENTS" | jq 'length')

    if [ "$AGENT_COUNT" -eq 0 ]; then
        fail_item "No agents registered"
    else
        ok "Agents registered: $AGENT_COUNT"

        # List agents
        echo "$AGENTS" | jq -r '.[] | "    - \(.name) (\(.role // "unknown"))"' 2>/dev/null || true

        # Check expected agents from template
        TEMPLATE_DIR="$REPO_ROOT/templates/solo-developer"
        if [ -f "$TEMPLATE_DIR/org.json" ]; then
            EXPECTED=$(jq -r '.agents[].name' "$TEMPLATE_DIR/org.json")
            while IFS= read -r expected_name; do
                found=$(echo "$AGENTS" | jq -r ".[] | select(.name == \"$expected_name\") | .name" 2>/dev/null)
                if [ -z "$found" ]; then
                    warn_item "Expected agent not found: $expected_name"
                fi
            done <<< "$EXPECTED"
        fi
    fi
fi

echo ""

# ─────────────────────────────────────────────
# 3. Hermes (COO)
# ─────────────────────────────────────────────

info "Hermes Agent (COO)"

if command -v hermes &>/dev/null; then
    ok "Hermes CLI installed"

    # Check config
    if [ -f "$HOME/.hermes/config.yaml" ]; then
        ok "Hermes config exists"
    else
        fail_item "Hermes config not found at ~/.hermes/config.yaml"
    fi

    # Check memory
    if [ -f "$HOME/.hermes/memories/MEMORY.md" ]; then
        mem_size=$(wc -c < "$HOME/.hermes/memories/MEMORY.md" | tr -d ' ')
        ok "COO memory seeded ($mem_size chars)"
    else
        warn_item "COO memory not seeded. See setup-guide.md §3.6"
    fi

    # Check .env
    if [ -f "$HOME/.hermes/.env" ]; then
        ok "Hermes .env exists"
        perms=$(stat -f "%Lp" "$HOME/.hermes/.env" 2>/dev/null || stat -c "%a" "$HOME/.hermes/.env" 2>/dev/null)
        if [ "$perms" = "600" ]; then
            ok "Hermes .env permissions: 600"
        else
            warn_item "Hermes .env permissions: $perms (should be 600)"
        fi
    else
        fail_item "Hermes .env not found"
    fi

    # Check cron jobs
    cron_output=$(hermes cron list 2>/dev/null || echo "")
    if echo "$cron_output" | grep -qi "daily\|briefing" 2>/dev/null; then
        ok "COO cron jobs configured"
    else
        warn_item "COO cron jobs not found. See setup-guide.md §3.7"
    fi
else
    fail_item "Hermes CLI not installed"
fi

echo ""

# ─────────────────────────────────────────────
# 4. Telegram gateway
# ─────────────────────────────────────────────

info "Telegram Gateway"

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    ok "TELEGRAM_BOT_TOKEN set"
else
    # Check in Hermes .env
    if [ -f "$HOME/.hermes/.env" ] && grep -q "TELEGRAM_BOT_TOKEN" "$HOME/.hermes/.env" 2>/dev/null; then
        ok "TELEGRAM_BOT_TOKEN set (in Hermes .env)"
    else
        warn_item "TELEGRAM_BOT_TOKEN not found. COO won't send Telegram alerts."
    fi
fi

echo ""

# ─────────────────────────────────────────────
# 5. Agent CLIs
# ─────────────────────────────────────────────

info "Agent CLIs"

if command -v claude &>/dev/null; then
    ok "Claude Code CLI: $(claude --version 2>/dev/null | head -1)"
else
    warn_item "Claude Code CLI not found"
fi

if command -v codex &>/dev/null; then
    ok "Codex CLI found"
else
    echo -e "  ${BLUE}-${NC} Codex CLI not installed (optional)"
fi

if command -v opencode &>/dev/null; then
    ok "OpenCode CLI found"
else
    echo -e "  ${BLUE}-${NC} OpenCode CLI not installed (optional)"
fi

echo ""

# ─────────────────────────────────────────────
# 6. Repository structure
# ─────────────────────────────────────────────

info "Repository Structure"

for dir in templates/solo-developer/prompts routines scripts data schemas docs; do
    if [ -d "$REPO_ROOT/$dir" ]; then
        ok "$dir/"
    else
        fail_item "$dir/ missing"
    fi
done

# Check prompt files
PROMPT_DIR="$REPO_ROOT/templates/solo-developer/prompts"
prompt_count=$(find "$PROMPT_DIR" -name "*.md" -not -name "_*" | wc -l | tr -d ' ')
preamble_exists=$([ -f "$PROMPT_DIR/_preamble.md" ] && echo "yes" || echo "no")

if [ "$preamble_exists" = "yes" ]; then
    ok "_preamble.md exists"
else
    fail_item "_preamble.md missing"
fi

ok "$prompt_count agent prompt files"

echo ""

# ─────────────────────────────────────────────
# 7. Data directories
# ─────────────────────────────────────────────

info "Data Directories"

for dir in data/events data/knowledge data/metrics data/snapshots; do
    if [ -d "$REPO_ROOT/$dir" ]; then
        file_count=$(find "$REPO_ROOT/$dir" -type f -not -name ".gitkeep" | wc -l | tr -d ' ')
        if [ "$file_count" -gt 0 ]; then
            ok "$dir/ ($file_count files)"
        else
            echo -e "  ${BLUE}-${NC} $dir/ (empty — will populate during operation)"
        fi
    else
        warn_item "$dir/ missing"
    fi
done

echo ""

# ─────────────────────────────────────────────
# Summary
# ─────────────────────────────────────────────

echo "════════════════════════"

if [ "$FAILURES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    echo -e "${GREEN}All checks passed. YantraForge is ready.${NC}"
elif [ "$FAILURES" -eq 0 ]; then
    echo -e "${YELLOW}$WARNINGS warning(s), 0 failures. YantraForge is operational with caveats.${NC}"
else
    echo -e "${RED}$FAILURES failure(s), $WARNINGS warning(s). Fix failures before proceeding.${NC}"
fi

echo ""
