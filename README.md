# YantraForge Core

[![CI](https://github.com/YantraForge-AI/core/actions/workflows/ci.yml/badge.svg)](https://github.com/YantraForge-AI/core/actions/workflows/ci.yml)

> Plug-and-play AI org-in-a-box built on [Paperclip](https://github.com/paperclipai/paperclip).

YantraForge provides org templates, principles-based agent prompts, and a COO-as-interface pattern that lets a single human run a multi-agent development organization.

## Quick Start

```bash
# Prerequisites: Node.js 20+, Python 3.11+, one agent CLI (Claude Code, Codex, or OpenCode)
npx paperclipai onboard --yes

git clone https://github.com/YantraForge-AI/core.git
cd core
cp .env.example .env
# Fill in your API keys

./scripts/init.sh
./scripts/verify.sh
```

## Templates

| Template | Agents | Monthly Budget | Use Case |
|---|---|---|---|
| `solo-developer` | 8 | ~$300 | Dogfooding, personal projects |
| `startup-team` | 14 | ~$450 | Engineering + product + content |
| `full-org` | 20 | ~$625 | Complete autonomous org |

## Architecture

```
You (CEO / Board)
  --> COO (Hermes Agent -- persistent memory, Telegram, cron)
    --> CTO --> Engineering Lead --> BE, QA
    --> CTO --> Research Lead --> Academic Researcher
    --> CMO --> Technical Writer
```

Scales from 8 to 20+ agents as pain demands.

## Quality Model

YantraForge uses **principles over procedures**:

- Quality comes from principles-rich agent prompts, not compliance checklists
- The org hierarchy (IC --> Lead --> CxO --> COO --> CEO) is the quality gate
- The COO observes patterns across sessions and proposes prompt updates
- Procedures are added only when specific failures are observed, not anticipated

## Documentation

- [Setup Guide](docs/quickstart.md) -- Zero to running org
- [Blueprint](https://github.com/YantraForge-AI/core/wiki) -- Full 20-agent reference architecture
- [Product Strategy](docs/product-strategy.md) -- Roadmap and vision

## Repository Structure

```
core/
  templates/          -- Org templates (solo-developer, startup-team, full-org)
  routines/           -- Paperclip routine configs (daily briefing, weekly digest)
  skills/             -- YantraForge-specific agent skills
  scripts/            -- CLI and setup scripts (init.sh, verify.sh)
  schemas/            -- JSON/YAML validation schemas
  data/               -- Runtime data (events, knowledge, metrics, snapshots)
  docs/               -- Documentation
  examples/           -- Example configurations
```

## Related Repositories

| Repo | Description |
|---|---|
| [.github](https://github.com/YantraForge-AI/.github) | Org profile and community health files |
| [skills](https://github.com/YantraForge-AI/skills) | Shared agent skills (coming soon) |
| [docs](https://github.com/YantraForge-AI/docs) | Documentation site (coming soon) |

## Built On

- [Paperclip](https://github.com/paperclipai/paperclip) -- Agent orchestration engine
- [Hermes Agent](https://github.com/NousResearch/hermes-agent) -- COO runtime (persistent memory, Telegram, cron)

## License

MIT
