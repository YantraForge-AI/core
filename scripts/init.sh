#!/usr/bin/env bash
set -euo pipefail

# YantraForge init.sh — Configure Paperclip from a template
# Usage: ./scripts/init.sh [template-name]
# Default template: solo-developer

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
# Step 0: Validate prerequisites
# ─────────────────────────────────────────────

info "YantraForge init — template: $TEMPLATE"
echo ""

# Check template exists
[ -d "$TEMPLATE_DIR" ] || fail "Template not found: $TEMPLATE_DIR"
[ -f "$TEMPLATE_DIR/org.json" ] || fail "Template missing org.json: $TEMPLATE_DIR/org.json"

# Check .env exists
if [ ! -f "$REPO_ROOT/.env" ]; then
    warn ".env not found. Copying from .env.example"
    cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
    warn "Fill in your API keys in .env before continuing"
    exit 1
fi

source "$REPO_ROOT/.env" 2>/dev/null || true

# Check Node.js
node_version=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
if [ -z "$node_version" ] || [ "$node_version" -lt 20 ]; then
    fail "Node.js 20+ required. Current: $(node -v 2>/dev/null || echo 'not found')"
fi
ok "Node.js $(node -v)"

# Check Python
python_version=$(python3 --version 2>/dev/null | cut -d' ' -f2 | cut -d. -f1-2)
if [ -z "$python_version" ]; then
    fail "Python 3.11+ required. Not found."
fi
ok "Python $python_version"

# Check at least one agent CLI
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

# Check Hermes (for COO)
if command -v hermes &>/dev/null; then
    ok "Hermes Agent found"
else
    warn "Hermes Agent not found. COO will not function. Install: curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash"
fi

# Check GitHub token
if [ -n "${GITHUB_TOKEN:-}" ]; then
    ok "GITHUB_TOKEN set"
else
    warn "GITHUB_TOKEN not set in .env — agents won't have GitHub access"
fi

# Check COO LLM provider key
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
    info "Starting Paperclip..."
    echo ""
    echo "  Run in a separate terminal:"
    echo "    npx paperclipai onboard --yes"
    echo ""
    echo "  Then re-run this script."
    exit 1
fi
ok "Paperclip server running"

echo ""

# ─────────────────────────────────────────────
# Step 2: Create company (if not exists)
# ─────────────────────────────────────────────

info "Configuring company..."

COMPANY_NAME=$(jq -r '.name' "$TEMPLATE_DIR/org.json")
NORTH_STAR=$(jq -r '.north_star' "$TEMPLATE_DIR/org.json")
BUDGET=$(jq -r '.budget_monthly_cents' "$TEMPLATE_DIR/org.json")

# Check if company already exists
existing=$(curl -sf "$API/companies" | jq -r ".[] | select(.name == \"$COMPANY_NAME\") | .id" 2>/dev/null || echo "")

if [ -n "$existing" ]; then
    COMPANY_ID="$existing"
    ok "Company '$COMPANY_NAME' exists (id: $COMPANY_ID)"
else
    info "Company '$COMPANY_NAME' not found — create it in the Paperclip dashboard:"
    echo ""
    echo "  1. Open $PAPERCLIP_URL"
    echo "  2. Click 'New Company'"
    echo "  3. Name: $COMPANY_NAME"
    echo "  4. Goal: $NORTH_STAR"
    echo "  5. Create the CEO agent (adapter: human or claude_local)"
    echo "  6. Set monthly budget: \$$(echo "scale=0; $BUDGET / 100" | bc)"
    echo ""
    echo "  Then re-run this script."
    exit 1
fi

echo ""

# ─────────────────────────────────────────────
# Step 3: Create Ops project for COO routines
# ─────────────────────────────────────────────

info "Checking for YantraForge Ops project..."

OPS_PROJECT=$(jq -r '.platform_constraints.ops_project' "$TEMPLATE_DIR/org.json")
# Note: Paperclip project creation may need to be done via UI
# This is a reminder check
info "Ensure project '$OPS_PROJECT' exists in Paperclip dashboard for COO routines"

echo ""

# ─────────────────────────────────────────────
# Step 4: Register agents
# ─────────────────────────────────────────────

info "Registering agents..."

AGENT_COUNT=$(jq '.agents | length' "$TEMPLATE_DIR/org.json")

for i in $(seq 0 $((AGENT_COUNT - 1))); do
    agent_name=$(jq -r ".agents[$i].name" "$TEMPLATE_DIR/org.json")
    agent_role=$(jq -r ".agents[$i].role" "$TEMPLATE_DIR/org.json")
    agent_adapter=$(jq -r ".agents[$i].adapter" "$TEMPLATE_DIR/org.json")
    agent_budget=$(jq -r ".agents[$i].budget_cents" "$TEMPLATE_DIR/org.json")
    agent_memory=$(jq -r ".agents[$i].memory" "$TEMPLATE_DIR/org.json")
    agent_cron=$(jq -r ".agents[$i].heartbeat_cron" "$TEMPLATE_DIR/org.json")
    agent_prompt_file=$(jq -r ".agents[$i].prompt" "$TEMPLATE_DIR/org.json")

    # Check if prompt file exists
    prompt_path="$TEMPLATE_DIR/$agent_prompt_file"
    if [ -f "$prompt_path" ]; then
        prompt_status="prompt ready"
    else
        prompt_status="prompt MISSING: $prompt_path"
    fi

    echo -e "  ${BLUE}[$((i+1))/$AGENT_COUNT]${NC} $agent_name ($agent_role)"
    echo "         adapter: $agent_adapter | budget: \$$(echo "scale=0; $agent_budget / 100" | bc)/mo | memory: $agent_memory"
    echo "         heartbeat: $agent_cron | $prompt_status"
done

echo ""
info "Agent registration requires the Paperclip dashboard UI."
info "For each agent above:"
echo "  1. Go to $PAPERCLIP_URL → Company → Add Agent"
echo "  2. Set name, role, adapter, manager, budget as shown"
echo "  3. Paste the prompt from the corresponding prompt file"
echo "  4. Set heartbeat cron expression"
echo "  5. Enable callback triggers (task_assigned)"
echo ""

# ─────────────────────────────────────────────
# Step 5: Platform constraints checklist
# ─────────────────────────────────────────────

info "Platform constraint checklist:"
echo ""

CONCURRENCY=$(jq -r '.platform_constraints.agent_concurrency' "$TEMPLATE_DIR/org.json")
HIRING_GATE=$(jq -r '.platform_constraints.agent_hiring_gate' "$TEMPLATE_DIR/org.json")
BUDGET_GATE=$(jq -r '.platform_constraints.budget_increases_gate' "$TEMPLATE_DIR/org.json")
HEARTBEAT_PROMPTS=$(jq -r '.platform_constraints.default_heartbeat_prompts' "$TEMPLATE_DIR/org.json")

echo "  [ ] Agent concurrency = $CONCURRENCY for all agents"
echo "      → Agent → Configuration → Advanced → Concurrency"
echo ""
echo "  [ ] agent_hiring gate = $HIRING_GATE"
echo "      → Company Settings → Approval & Governance"
echo ""
echo "  [ ] budget_increases gate = $BUDGET_GATE"
echo "      → Company Settings → Approval & Governance"
echo ""
echo "  [ ] Default heartbeat prompts: $HEARTBEAT_PROMPTS"
echo "      → Remove paperclip-ic.md / paperclip-pm.md from each agent"
echo "      → Use YantraForge prompts exclusively"
echo ""
echo "  [ ] Skills scoping verified"
echo "      → Install a test skill, check if all agents see it"
echo "      → If company-scoped: constrain via prompts, not adapter config"
echo ""
echo "  [ ] '$OPS_PROJECT' project exists for COO routines"
echo ""

# ─────────────────────────────────────────────
# Step 6: Memory tier configuration
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
# Step 7: Summary
# ─────────────────────────────────────────────

TOTAL_BUDGET=$(jq '[.agents[].budget_cents] | add' "$TEMPLATE_DIR/org.json")
OPS_BUFFER=$((BUDGET - TOTAL_BUDGET))

echo "─────────────────────────────────────────────"
info "Summary"
echo ""
echo "  Company:    $COMPANY_NAME"
echo "  Template:   $TEMPLATE"
echo "  Agents:     $AGENT_COUNT"
echo "  Budget:     \$$(echo "scale=0; $TOTAL_BUDGET / 100" | bc)/mo (agents) + \$$(echo "scale=0; $OPS_BUFFER / 100" | bc)/mo (ops buffer) = \$$(echo "scale=0; $BUDGET / 100" | bc)/mo"
echo "  Agent CLI:  $agent_cli"
echo ""
echo "  Next steps:"
echo "    1. Register agents in Paperclip dashboard (see list above)"
echo "    2. Enforce platform constraints (see checklist above)"
echo "    3. Set up Hermes for COO (see setup-guide.md Part 3)"
echo "    4. Run: ./scripts/verify.sh"
echo "─────────────────────────────────────────────"
