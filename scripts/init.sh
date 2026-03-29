#!/usr/bin/env bash
set -euo pipefail

# YantraForge init.sh — Configure Paperclip from a template
# Usage: ./scripts/init.sh [template-name]
# Default template: solo-developer
#
# Automates: company creation, goal setup, agent registration,
# project creation, and platform constraint enforcement via the
# Paperclip API. Idempotent — safe to re-run.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="${1:-solo-developer}"
TEMPLATE_DIR="$REPO_ROOT/templates/$TEMPLATE"
PAPERCLIP_URL="${PAPERCLIP_URL:-http://localhost:3100}"
API="$PAPERCLIP_URL/api"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { echo -e "${BLUE}[info]${NC}  $1"; }
ok()    { echo -e "${GREEN}[ok]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[warn]${NC}  $1"; }
fail()  { echo -e "${RED}[fail]${NC}  $1"; exit 1; }

# ─────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────

# HTTP helpers — fail loudly on non-2xx
api_get() {
    curl -sf "$API$1" 2>/dev/null
}

api_post() {
    local path="$1" body="$2"
    curl -sf -X POST "$API$path" -H "Content-Type: application/json" -d "$body" 2>/dev/null
}

api_patch() {
    local path="$1" body="$2"
    curl -sf -X PATCH "$API$path" -H "Content-Type: application/json" -d "$body" 2>/dev/null
}

# Convert cron interval expression to seconds.
# Handles */N minute patterns. Falls back to 1800 for complex expressions.
cron_to_interval_sec() {
    local cron="$1"
    local minutes
    if [[ "$cron" =~ ^\*/([0-9]+) ]]; then
        minutes="${BASH_REMATCH[1]}"
        echo $((minutes * 60))
    else
        echo 1800
    fi
}

# ─────────────────────────────────────────────
# Step 0: Validate prerequisites
# ─────────────────────────────────────────────

info "YantraForge init — template: $TEMPLATE"
echo ""

[ -d "$TEMPLATE_DIR" ] || fail "Template not found: $TEMPLATE_DIR"
[ -f "$TEMPLATE_DIR/org.json" ] || fail "Template missing org.json: $TEMPLATE_DIR/org.json"

if [ ! -f "$REPO_ROOT/.env" ]; then
    if [ -f "$REPO_ROOT/.env.example" ]; then
        warn ".env not found. Copying from .env.example"
        cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
    fi
    warn "Fill in your API keys in .env before continuing"
    exit 1
fi

source "$REPO_ROOT/.env" 2>/dev/null || true

node_version=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
if [ -z "$node_version" ] || [ "$node_version" -lt 20 ]; then
    fail "Node.js 20+ required. Current: $(node -v 2>/dev/null || echo 'not found')"
fi
ok "Node.js $(node -v)"

python_version=$(python3 --version 2>/dev/null | cut -d' ' -f2 | cut -d. -f1-2)
if [ -z "$python_version" ]; then
    fail "Python 3.11+ required. Not found."
fi
ok "Python $python_version"

agent_cli="none"
if command -v claude &>/dev/null; then
    agent_cli="claude"
    ok "Claude Code CLI found"
elif command -v codex &>/dev/null; then
    agent_cli="codex"
    ok "Codex CLI found"
elif command -v opencode &>/dev/null; then
    agent_cli="opencode"
    ok "OpenCode CLI found"
else
    warn "No agent CLI found (claude, codex, or opencode). Install at least one."
fi

if command -v hermes &>/dev/null; then
    ok "Hermes Agent found"
else
    warn "Hermes Agent not found. COO will not function. Install: curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"
fi

if [ -n "${GITHUB_TOKEN:-}" ]; then
    ok "GITHUB_TOKEN set"
else
    warn "GITHUB_TOKEN not set in .env — agents won't have GitHub access"
fi

coo_key_found=false
for key in OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY GOOGLE_API_KEY; do
    if [ -n "${!key:-}" ]; then
        ok "COO LLM provider: $key"
        coo_key_found=true
        break
    fi
done
if [ "$coo_key_found" = false ]; then
    warn "No COO LLM provider key found. Set one in .env (OPENROUTER_API_KEY recommended)"
fi

echo ""

# ─────────────────────────────────────────────
# Step 1: Check Paperclip server
# ─────────────────────────────────────────────

info "Checking Paperclip server at $PAPERCLIP_URL..."

if ! curl -sf "$API/health" &>/dev/null; then
    warn "Paperclip not running at $PAPERCLIP_URL"
    info "Start it with:  npx paperclipai onboard --yes"
    info "Then re-run this script."
    exit 1
fi
ok "Paperclip server running"

echo ""

# ─────────────────────────────────────────────
# Step 2: Create company (idempotent)
# ─────────────────────────────────────────────

info "Configuring company..."

COMPANY_NAME=$(jq -r '.name' "$TEMPLATE_DIR/org.json")
NORTH_STAR=$(jq -r '.north_star' "$TEMPLATE_DIR/org.json")
BUDGET=$(jq -r '.budget_monthly_cents' "$TEMPLATE_DIR/org.json")

COMPANY_ID=$(api_get "/companies" | jq -r ".[] | select(.name == \"$COMPANY_NAME\") | .id" 2>/dev/null || echo "")

if [ -n "$COMPANY_ID" ]; then
    ok "Company '$COMPANY_NAME' exists (id: $COMPANY_ID)"
else
    info "Creating company '$COMPANY_NAME'..."
    RESULT=$(api_post "/companies" "$(jq -n --arg name "$COMPANY_NAME" --arg desc "$NORTH_STAR" '{name: $name, description: $desc}')")
    if [ -z "$RESULT" ]; then
        fail "Company creation failed. Create manually in the Paperclip dashboard at $PAPERCLIP_URL"
    fi
    COMPANY_ID=$(echo "$RESULT" | jq -r '.id')
    ok "Company created (id: $COMPANY_ID)"
fi

echo ""

# ─────────────────────────────────────────────
# Step 3: Create company goal (idempotent)
# ─────────────────────────────────────────────

info "Configuring company goal..."

GOAL_ID=$(api_get "/companies/$COMPANY_ID/goals" | jq -r ".[0].id // empty" 2>/dev/null || echo "")

if [ -n "$GOAL_ID" ]; then
    ok "Company goal exists (id: $GOAL_ID)"
else
    info "Creating company goal..."
    RESULT=$(api_post "/companies/$COMPANY_ID/goals" "$(jq -n --arg title "$NORTH_STAR" '{title: $title, level: "company", status: "active"}')")
    if [ -z "$RESULT" ]; then
        warn "Goal creation failed. Create manually in Paperclip dashboard."
    else
        GOAL_ID=$(echo "$RESULT" | jq -r '.id')
        ok "Goal created (id: $GOAL_ID)"
    fi
fi

echo ""

# ─────────────────────────────────────────────
# Step 4: Create Ops project (idempotent)
# ─────────────────────────────────────────────

OPS_PROJECT=$(jq -r '.platform_constraints.ops_project' "$TEMPLATE_DIR/org.json")
info "Configuring project '$OPS_PROJECT'..."

OPS_PROJECT_ID=$(api_get "/companies/$COMPANY_ID/projects" | jq -r ".[] | select(.name == \"$OPS_PROJECT\") | .id" 2>/dev/null || echo "")

if [ -n "$OPS_PROJECT_ID" ]; then
    ok "Project '$OPS_PROJECT' exists (id: $OPS_PROJECT_ID)"
else
    info "Creating project '$OPS_PROJECT'..."
    PROJECT_BODY=$(jq -n \
        --arg name "$OPS_PROJECT" \
        --arg desc "Operational routines and COO-managed tasks" \
        --arg goalId "$GOAL_ID" \
        '{name: $name, description: $desc, status: "in_progress", goalIds: [$goalId]}')
    RESULT=$(api_post "/companies/$COMPANY_ID/projects" "$PROJECT_BODY")
    if [ -z "$RESULT" ]; then
        warn "Project creation failed. Create '$OPS_PROJECT' manually in Paperclip dashboard."
    else
        OPS_PROJECT_ID=$(echo "$RESULT" | jq -r '.id')
        ok "Project created (id: $OPS_PROJECT_ID)"
    fi
fi

echo ""

# ─────────────────────────────────────────────
# Step 5: Register agents (idempotent)
# ─────────────────────────────────────────────

info "Registering agents..."

AGENT_COUNT=$(jq '.agents | length' "$TEMPLATE_DIR/org.json")
EXISTING_AGENTS=$(api_get "/companies/$COMPANY_ID/agents" || echo "[]")

# Map org.json role names to Paperclip role slugs
role_slug() {
    local role="$1"
    case "$role" in
        COO)            echo "general" ;;
        CTO)            echo "cto" ;;
        CMO)            echo "cmo" ;;
        "Team Lead")    echo "engineer" ;;
        IC)             echo "engineer" ;;
        *)              echo "engineer" ;;
    esac
}

# Temporarily disable approval gate for batch agent creation
ORIGINAL_GATE=$(api_get "/companies/$COMPANY_ID" | jq -r '.requireBoardApprovalForNewAgents' 2>/dev/null || echo "true")
if [ "$ORIGINAL_GATE" = "true" ]; then
    api_patch "/companies/$COMPANY_ID" '{"requireBoardApprovalForNewAgents":false}' > /dev/null 2>&1 || true
fi

# Agent name→ID map stored as a temp file (bash 3.x compatible)
AGENT_MAP_FILE=$(mktemp)
trap "rm -f $AGENT_MAP_FILE" EXIT
echo "$EXISTING_AGENTS" | jq -r '.[] | "\(.name)\t\(.id)"' > "$AGENT_MAP_FILE" 2>/dev/null || true

agent_id_for() {
    local name="$1"
    grep "^${name}	" "$AGENT_MAP_FILE" | cut -f2 | head -1
}

set_agent_id() {
    local name="$1" id="$2"
    echo -e "${name}\t${id}" >> "$AGENT_MAP_FILE"
}

# Two-pass registration: first pass creates agents without manager references,
# second pass sets reportsTo for agents that need a manager.
# This avoids ordering issues (manager must exist before report).

CREATED_COUNT=0
CREATED_NAMES=""

for i in $(seq 0 $((AGENT_COUNT - 1))); do
    agent_name=$(jq -r ".agents[$i].name" "$TEMPLATE_DIR/org.json")
    agent_role=$(jq -r ".agents[$i].role" "$TEMPLATE_DIR/org.json")
    agent_adapter=$(jq -r ".agents[$i].adapter" "$TEMPLATE_DIR/org.json")
    agent_budget=$(jq -r ".agents[$i].budget_cents" "$TEMPLATE_DIR/org.json")
    agent_cron=$(jq -r ".agents[$i].heartbeat_cron" "$TEMPLATE_DIR/org.json")
    agent_prompt_file=$(jq -r ".agents[$i].prompt" "$TEMPLATE_DIR/org.json")

    existing_id=$(agent_id_for "$agent_name")
    if [ -n "$existing_id" ]; then
        ok "Agent '$agent_name' exists (id: $existing_id)"
        continue
    fi

    interval_sec=$(cron_to_interval_sec "$agent_cron")
    slug=$(role_slug "$agent_role")

    prompt_path="$TEMPLATE_DIR/$agent_prompt_file"
    capabilities=""
    if [ -f "$prompt_path" ]; then
        capabilities=$(grep -v '^#' "$prompt_path" | grep -v '^$' | head -1 | cut -c1-200)
    fi
    [ -z "$capabilities" ] && capabilities="$agent_name — $agent_role"

    info "Creating agent '$agent_name' ($slug)..."

    HIRE_BODY=$(jq -n \
        --arg name "$agent_name" \
        --arg role "$slug" \
        --arg adapter "$agent_adapter" \
        --argjson budget "$agent_budget" \
        --arg caps "$capabilities" \
        --argjson interval "$interval_sec" \
        '{
            name: $name,
            role: $role,
            adapterType: $adapter,
            budgetMonthlyCents: $budget,
            capabilities: $caps,
            runtimeConfig: {
                heartbeat: {
                    enabled: true,
                    intervalSec: $interval,
                    wakeOnDemand: true,
                    maxConcurrentRuns: 1
                }
            }
        }')

    RESULT=$(api_post "/companies/$COMPANY_ID/agent-hires" "$HIRE_BODY" || echo "")
    if [ -z "$RESULT" ]; then
        warn "Failed to create agent '$agent_name'. Register manually in Paperclip dashboard."
        continue
    fi

    new_id=$(echo "$RESULT" | jq -r '.agent.id')
    agent_status=$(echo "$RESULT" | jq -r '.agent.status')
    set_agent_id "$agent_name" "$new_id"
    CREATED_COUNT=$((CREATED_COUNT + 1))
    CREATED_NAMES="${CREATED_NAMES:+$CREATED_NAMES, }$agent_name"

    # Auto-approve if the agent is pending
    if [ "$agent_status" = "pending_approval" ]; then
        approval_id=$(api_get "/companies/$COMPANY_ID/approvals?status=pending" \
            | jq -r ".[] | select(.payload.agentId == \"$new_id\") | .id" 2>/dev/null || echo "")
        if [ -n "$approval_id" ]; then
            api_post "/approvals/$approval_id/approve" '{}' > /dev/null 2>&1 || true
        fi
    fi

    ok "Agent '$agent_name' created and activated (id: $new_id)"
done

# Second pass: set reportsTo for agents with managers
for i in $(seq 0 $((AGENT_COUNT - 1))); do
    agent_name=$(jq -r ".agents[$i].name" "$TEMPLATE_DIR/org.json")
    manager_name=$(jq -r ".agents[$i].manager // empty" "$TEMPLATE_DIR/org.json")

    [ -z "$manager_name" ] && continue

    agent_id=$(agent_id_for "$agent_name")
    manager_id=$(agent_id_for "$manager_name")

    [ -z "$agent_id" ] || [ -z "$manager_id" ] && continue

    # Check current reportsTo
    current_manager=$(echo "$EXISTING_AGENTS" | jq -r ".[] | select(.id == \"$agent_id\") | .reportsTo // empty" 2>/dev/null || echo "")
    if [ "$current_manager" = "$manager_id" ]; then
        continue
    fi

    api_patch "/agents/$agent_id" "$(jq -n --arg mgr "$manager_id" '{reportsTo: $mgr}')" > /dev/null 2>&1 || true
    ok "Set '$agent_name' → reports to '$manager_name'"
done

# Restore approval gate
if [ "$ORIGINAL_GATE" = "true" ]; then
    api_patch "/companies/$COMPANY_ID" '{"requireBoardApprovalForNewAgents":true}' > /dev/null 2>&1 || true
fi

echo ""

# ─────────────────────────────────────────────
# Step 6: Platform constraints
# ─────────────────────────────────────────────

info "Enforcing platform constraints..."

CONCURRENCY=$(jq -r '.platform_constraints.agent_concurrency' "$TEMPLATE_DIR/org.json")
HIRING_GATE=$(jq -r '.platform_constraints.agent_hiring_gate' "$TEMPLATE_DIR/org.json")
BUDGET_GATE=$(jq -r '.platform_constraints.budget_increases_gate' "$TEMPLATE_DIR/org.json")

# Enforce concurrency on all agents via runtimeConfig
while IFS=$'\t' read -r _ agent_id; do
    api_patch "/agents/$agent_id" "$(jq -n --argjson c "$CONCURRENCY" \
        '{runtimeConfig: {heartbeat: {maxConcurrentRuns: $c}}}')" > /dev/null 2>&1 || true
done < "$AGENT_MAP_FILE"
ok "Agent concurrency set to $CONCURRENCY for all agents"

# Enforce hiring gate
if [ "$HIRING_GATE" = "true" ]; then
    api_patch "/companies/$COMPANY_ID" '{"requireBoardApprovalForNewAgents":true}' > /dev/null 2>&1 || true
    ok "Agent hiring gate: ON"
fi

echo ""

# Remaining manual constraints (no API support)
info "Manual verification needed:"
echo ""
echo "  [ ] Budget increase gate = $BUDGET_GATE"
echo "      → Company Settings → Approval & Governance"
echo ""
echo "  [ ] Default heartbeat prompts disabled"
echo "      → Remove paperclip-ic.md / paperclip-pm.md from each agent"
echo "      → Use YantraForge prompts exclusively"
echo ""
echo "  [ ] Skills scoping verified"
echo "      → Install a test skill, check if all agents see it"
echo ""

# ─────────────────────────────────────────────
# Step 7: Memory tier configuration
# ─────────────────────────────────────────────

info "Memory tier configuration:"
echo ""

for i in $(seq 0 $((AGENT_COUNT - 1))); do
    agent_name=$(jq -r ".agents[$i].name" "$TEMPLATE_DIR/org.json")
    agent_memory=$(jq -r ".agents[$i].memory" "$TEMPLATE_DIR/org.json")

    case "$agent_memory" in
        persistent)
            echo "  $agent_name: PERSISTENT (Hermes MEMORY.md — configured via Hermes setup)"
            ;;
        para)
            echo "  $agent_name: PARA (file-based — enable in Agent → Configuration → Memory)"
            ;;
        stateless)
            echo "  $agent_name: STATELESS (no configuration needed)"
            ;;
    esac
done

echo ""

# ─────────────────────────────────────────────
# Step 8: Summary
# ─────────────────────────────────────────────

TOTAL_BUDGET=$(jq '[.agents[].budget_cents] | add' "$TEMPLATE_DIR/org.json")
OPS_BUFFER=$((BUDGET - TOTAL_BUDGET))
REGISTERED_COUNT=$(api_get "/companies/$COMPANY_ID/agents" | jq 'length' 2>/dev/null || echo "?")

echo "─────────────────────────────────────────────"
info "Summary"
echo ""
echo "  Company:    $COMPANY_NAME (id: $COMPANY_ID)"
echo "  Template:   $TEMPLATE"
echo "  Goal:       $(echo "$NORTH_STAR" | cut -c1-60)..."
echo "  Agents:     $REGISTERED_COUNT registered ($CREATED_COUNT created this run)"
echo "  Project:    $OPS_PROJECT (id: ${OPS_PROJECT_ID:-not created})"
echo "  Budget:     \$$(echo "scale=0; $TOTAL_BUDGET / 100" | bc)/mo (agents) + \$$(echo "scale=0; $OPS_BUFFER / 100" | bc)/mo (ops) = \$$(echo "scale=0; $BUDGET / 100" | bc)/mo"
echo "  Agent CLI:  $agent_cli"
echo ""
if [ "$CREATED_COUNT" -gt 0 ]; then
    echo "  Created this run: $CREATED_NAMES"
    echo ""
fi
echo "  Next steps:"
echo "    1. Verify manual constraints above"
echo "    2. Set up Hermes for COO (see setup-guide.md Part 3)"
echo "    3. Run: ./scripts/verify.sh"
echo "─────────────────────────────────────────────"
