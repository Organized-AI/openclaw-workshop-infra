# openclaw-workshop-infra

Infrastructure design, architecture docs, and presentation assets for the **OpenClaw Part 1–5 Workshop Series** by [Organized AI](https://organizedai.vip).

## What's in here

| File | Description |
|------|-------------|
| `docs/openclaw-gateway-hybrid-v2.html` | Full hybrid architecture — CF Queue + Durable Objects + D1 + prompt_logs observability |
| `docs/openclaw-part1-harness.html` | Part 1 event presentation — harness-first architecture for non-technical audiences |
| `docs/openclaw-gateway-architecture.html` | Gateway overview — 50-attendee WhatsApp flow, KV/D1 data model, breakaway export |
| `docs/openclaw-part1.html` | Original Part 1 deck — 14 slides, series map, full architecture |
| `assets/do-vs-cfq.jsx` | React artifact — Durable Objects vs CF Queues interactive comparison |
| `assets/openclaw-linkedin-v2.jsx` | LinkedIn promo post renderer for Part 1 |

## Architecture Summary

```
50 Attendees (WhatsApp)
    ↓
Meta Cloud API → organized-gateway Worker
    ↓
CF Queue: oc-messages          ← delivery guarantees + retries + DLQ
    ↓
Consumer Worker → USER_DO (per phone number)
    ↓
Durable Object per user        ← persistent state + controlled drain
  ├─ SOUL.md (per-user, editable via !soul)
  ├─ AGENTS.md (per-user, editable via !agents)
  ├─ BYOK api_key (supplied at setup)
  ├─ queue + 2s alarm drain
  └─ log_buffer → D1 batch flush
    ↓
OpenClaw on claws-mac-mini (Tailscale: 100.82.244.127)
    ↓
D1: oc_gateway_db              ← prompt_logs for routing + fine-tuning analysis
R2: oc-exports                 ← breakaway export packages
```

## Token Observability

`prompt_logs` D1 table captures per-turn: system prompt, user message, assistant reply, difficulty tier (SIMPLE/MEDIUM/COMPLEX), model used, token counts, tool calls, latency, and user feedback. Feeds:

- **[UncommonRoute / IYKYK](https://github.com/anjieyang/IYKYK)** — offline routing analysis, ~90-95% cost reduction recommendations
- **[CodeBurn](https://github.com/Organized-AI/codeburn)** — token observability TUI dashboard via JSONL export

## WhatsApp Commands (per-user)

| Command | Action |
|---------|--------|
| `!status` | queue depth, tokens used, last active |
| `!soul [text]` | update SOUL.md in DO storage |
| `!agents [text]` | update AGENTS.md |
| `!key [sk-...]` | replace BYOK API key |
| `!export` | trigger D1 export → R2 zip → signed URL DM |
| `!good` / `!bad` / `!pin` | quality feedback → prompt_logs |
| `!clear` | reset OpenClaw session |

## Cloudflare Resources (your account: 691fe25d377abac03627d6a88d3eeac9)

| Resource | Binding | Notes |
|----------|---------|-------|
| KV: sessions | `GATEWAY_KV` | id: 104c355b4c504bc6a8fafd846034e35f (existing) |
| D1: oc_gateway_db | `OC_DB` | create: `wrangler d1 create oc_gateway_db` |
| Queue: oc-messages | `OC_QUEUE` | create: `wrangler queues create oc-messages` |
| Queue: oc-messages-dlq | DLQ | create: `wrangler queues create oc-messages-dlq` |
| DO: UserSession | `USER_DO` | defined in wrangler.toml migrations |
| R2: oc-exports | `OC_EXPORTS` | create: `wrangler r2 bucket create oc-exports` |

## Event Series

| Part | Topic | Status |
|------|-------|--------|
| Part 1 | Architecture & The Harness | ✓ Designed |
| Part 2 | Channels & Sessions | Planned |
| Part 3 | Agent & Persona | Planned |
| Part 4 | Skills & Nodes | Planned |
| Part 5 | Security & Production | Planned |

Register: [lu.ma/1l21y2zh](https://lu.ma/1l21y2zh)

## Resources

- Guide: [guide.organizedai.vip/openclaw-gateway](https://guide.organizedai.vip/openclaw-gateway)
- Wiki: [wiki.organizedai.vip/openclaw](https://wiki.organizedai.vip/openclaw)
- Harness wiki: [wiki.organizedai.vip/harness](https://wiki.organizedai.vip/harness)
- Education: [guide.organizedai.vip/openclaw-education](https://guide.organizedai.vip/openclaw-education)

---

Maintained by Jordaaan Hill ([LinkedIn](https://www.linkedin.com/in/jordaaanhill)).
