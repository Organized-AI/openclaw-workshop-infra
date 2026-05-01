# Claude Code Build Prompt — organized-gateway

## Context
Building the organized-gateway Cloudflare Worker for the OpenClaw Part 1 workshop.
Full architecture in `docs/openclaw-gateway-hybrid-v2.html`.
D1 schema in `migrations/0001_initial.sql`.
Stub code in `src/`.

## Stack
- Cloudflare Worker (TypeScript, Hono)
- Durable Objects (UserSession class)
- CF Queue (producer + consumer)
- D1 database (oc_gateway_db)
- R2 bucket (oc-exports)
- KV namespace (GATEWAY_KV)
- Meta WhatsApp Cloud API
- OpenClaw on Tailscale (100.82.244.127)

## Phase 0 — bootstrap
Use Organized Codebase template. Run:
```
claude --dangerously-skip-permissions
```

Read all agents from .claude/agents/, pull relevant skills from
github.com/Organized-AI/claude-skills-worth-using and
github.com/Organized-AI/plugin-marketplace.

## Phase 1 — Cloudflare provisioning
```bash
wrangler d1 create oc_gateway_db
wrangler d1 execute oc_gateway_db --file migrations/0001_initial.sql
wrangler queues create oc-messages
wrangler queues create oc-messages-dlq
wrangler r2 bucket create oc-exports
# Update wrangler.toml with the new D1 database_id
```

## Phase 2 — Worker implementation
Build out `src/index.ts` and `src/durable-objects/UserSession.ts`:

### organized-gateway Worker (src/index.ts)
1. GET /webhook/whatsapp — Meta verify_token handshake
2. POST /webhook/whatsapp:
   - Verify X-Hub-Signature-256 against WEBHOOK_SECRET
   - KV lookup: wa_phone:{phone} → user_id
   - If not found: register new user (write KV, insert D1 attendees, send provisioning DM)
   - Push to CF Queue: env.OC_QUEUE.send({user_id, phone, body, message_id})
   - Return HTTP 200 immediately
3. async queue(batch) consumer:
   - For each message: route to user's DO via idFromName(user_id)
4. GET /admin/replay?msg_id= — replay failed message from D1 failed_messages

### UserSession Durable Object (src/durable-objects/UserSession.ts)
Storage keys:
- user_id, api_key (encrypted), api_provider
- soul_md, agents_md
- oc_session_id, msg_count, tokens_used, last_active, tier
- log_buffer (array, flush to D1 when ≥20 or 10s)
- queue (array of pending messages)

Methods:
- enqueue(message): push to queue, set alarm if none scheduled
- alarm(): pop queue[0], drain to OpenClaw, handle retries (3x, 30s/60s backoff), log to D1, reschedule if queue non-empty
- handleCommand(cmd): intercept !soul, !agents, !key, !status, !export, !good, !bad, !pin, !clear

Drain to OpenClaw:
- Load soul_md + agents_md from storage
- POST to env.OPENCLAW_URL/v1/chat/completions
  Headers: X-User-ID, X-Session-ID
  Body: {model, messages: [{role:system,content:soul_md+agents_md},{role:user,content:body}]}
  Auth: Bearer {api_key}
- On success: send WhatsApp reply via Meta API, append to log_buffer
- On failure: increment attempts, reschedule, DLQ after 3 failures

prompt_logs recording (after reply sent, zero latency impact):
- Run UncommonRoute difficulty classifier on user_message (cached, local)
- Calculate cost_usd from token counts × LiteLLM pricing
- Append to log_buffer: {id, user_id, session_id, ts, system_prompt, user_message,
  assistant_reply, model_requested, model_used, difficulty_tier, difficulty_score,
  prompt_tokens, completion_tokens, cache_read_tokens, cache_write_tokens,
  total_tokens, cost_usd, tool_calls_json, task_category, latency_ms}
- Flush log_buffer to D1 prompt_logs when ≥20 rows or 10s elapsed

## Phase 3 — OpenClaw config
On claws-mac-mini (100.82.244.127):
- Enable WhatsApp channel adapter in ~/.openclaw/openclaw.json
- Write default workshop SOUL.md to KV soul_md:default
- Write default workshop AGENTS.md to KV agents_md:default
- Test: message → DO → OpenClaw → WhatsApp reply

## Phase 4 — Event onboarding
- Generate WhatsApp group invite QR code
- Test full flow: join group → provisioning DM → !key reply → first message
- Test with 5 different phone numbers

## Phase 5 — Export Worker (post-event)
Add !export command handler to DO:
- INSERT exports row, set KV export:{user_id} = {status:'building'}
- Query D1 messages + prompt_logs for user
- Package: messages.json, soul_md.md, agents_md.md, openclaw_config.json,
  .env.template, setup.sh, README.md
- Upload zip to R2: oc-exports/{user_id}/{timestamp}.zip
- Generate 24hr signed URL
- Send WhatsApp DM with download link

## Environment variables needed
Set via `wrangler secret put <NAME>`:
- WEBHOOK_SECRET
- OPENCLAW_URL (http://100.82.244.127:18789 or Tailscale URL)
- META_ACCESS_TOKEN
- META_PHONE_ID
- ADMIN_PHONE (Jordan's number for DLQ alerts)
- ENCRYPTION_KEY (32 random bytes, base64)
