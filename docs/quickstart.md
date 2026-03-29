# Quickstart: Zero to Running Org

Get an 8-agent YantraForge org running on your machine in ~30 minutes.

## Prerequisites

- macOS, Linux, or WSL2
- Node.js 20+ (`node -v`)
- Python 3.11+ (`python3 --version`)
- At least one agent CLI: Claude Code (`npm install -g @anthropic-ai/claude-code`), Codex, or OpenCode
- Git

## Step 1: Install Paperclip

```bash
npx paperclipai onboard --yes
```

This starts the Paperclip server at `http://localhost:3100` with an embedded database.

## Step 2: Clone and Configure

```bash
git clone https://github.com/YantraForge-AI/core.git
cd core

cp .env.example .env
# Edit .env: add your GITHUB_TOKEN and one COO LLM provider key
# (OPENROUTER_API_KEY recommended — see .env.example for all options)
```

## Step 3: Run Init

```bash
./scripts/init.sh
```

This validates your prerequisites, checks Paperclip is running, and prints a guided checklist for registering your 8 agents.

## Step 4: Create Company in Paperclip

Open `http://localhost:3100`:

1. **New Company** → Name: `YantraForge`
2. **Goal:** `Build and ship AI-powered products with an 8-agent autonomous org`
3. **Create CEO agent** (placeholder — you are the CEO)
4. **Set budget:** $300/mo

## Step 5: Register Agents

Register each agent in the Paperclip dashboard. The init script printed the full list. For each agent:

1. Add Agent → set name, role, adapter type, manager, budget
2. Paste the prompt from `templates/solo-developer/prompts/{agent}.md`
   - Prepend `templates/solo-developer/prompts/_preamble.md` to every prompt
3. Set heartbeat cron (from `org.json`)
4. Enable callback trigger: `task_assigned`

**Platform constraints (enforce these):**

- Agent concurrency = 1 (Agent → Configuration → Advanced)
- `agent_hiring` approval gate = ON (Company Settings → Approval & Governance)
- `budget_increases` approval gate = ON
- Disable Paperclip's default heartbeat prompts (paperclip-ic.md / paperclip-pm.md)
- Create a project named "YantraForge Ops" for COO routines

**Memory tiers:**

| Agent | Memory |
|---|---|
| COO | Persistent (Hermes — see Step 6) |
| CTO, CMO, Engineering Lead, Research Lead | Para (enable in Agent → Configuration → Memory) |
| Backend Engineer, QA, Academic Researcher, Technical Writer | Stateless (default) |

## Step 6: Set Up Hermes (COO)

```bash
# Install
curl -fsSL https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh | bash
source ~/.zshrc

# Configure model
hermes model
# Select your provider and model (OpenRouter + claude-sonnet-4 recommended)

# Set API keys
# Edit ~/.hermes/.env with your provider key and Telegram tokens
chmod 600 ~/.hermes/.env

# Seed memory
cat > ~/.hermes/memories/MEMORY.md << 'EOF'
YantraForge COO. Report to Tom (CEO) via Telegram.§6 responsibilities: CEO interface, daily briefing, pattern recognition, prompt evolution, coordination nudges, org repo maintenance.§Org: 8 agents (starter). Budget: $300/mo.§Quality model: principles in prompts, hierarchy is the quality gate. No rubrics, no SLA crons. Add procedures only when specific failure is observed.
EOF

# Set up Telegram (optional but recommended)
hermes gateway setup

# Set up cron jobs
hermes cron start
hermes
/cron add "0 9 * * *" "Daily briefing for CEO. What shipped, what's stuck, CEO attention items. Keep short. Deliver via Telegram."
/cron add "0 10 * * 1" "Weekly digest: what shipped, what's blocked, budget, recurring patterns, prompt evolution proposals. Export memory snapshot to data/snapshots/."
```

## Step 7: Verify

```bash
./scripts/verify.sh
```

All checks should pass or show only warnings (no failures).

## Step 8: First Task

Send a message to your COO via Telegram (or the Paperclip dashboard):

```
"Compile an initial org status report. List all agents, their status, and any pending work."
```

Watch the COO pick it up, process it, and respond.

## Step 9: First Engineering Loop

Create a task assigned to the CTO:

```
"Create a hello-world Python project in the core repo with a single test"
```

Watch the cascade:
1. CTO decomposes → Engineering Lead
2. Engineering Lead creates subtasks → Backend Engineer (code) + QA (test)
3. Backend Engineer writes code, sets to in_review
4. QA validates, approves or rejects
5. Engineering Lead merges

If this completes without manual intervention, your org is working.

## What's Next

- **Use it for real work.** Don't keep testing — give it a real task.
- **Size every task** with XS/S/M/L/XL when creating it.
- **Watch for the first prompt evolution.** After a week, the COO should notice recurring patterns and propose a prompt update.
- **Check the procedure reintroduction triggers** in the blueprint monthly. Add procedures only when triggered.
- See `product-strategy.md` for the full sprint plan.
