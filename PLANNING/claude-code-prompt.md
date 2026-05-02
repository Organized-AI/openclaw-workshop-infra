# Claude Code Build Prompt — organized-gateway
## openclaw-workshop-infra · Phase 0 → Phase 4

---

## COPY THIS INTO CLAUDE CODE:

You are building the organized-gateway Cloudflare Worker for the OpenClaw Part 1 workshop infrastructure. This is the backend that handles 50 WhatsApp attendees through a hybrid CF Queue + Durable Objects architecture, routing messages to OpenClaw on claws-mac-mini via Tailscale.

## PHASE 0 — BOOTSTRAP

Run: claude --dangerously-skip-permissions

cd "/Users/supabowl/Library/Mobile Documents/com~apple~CloudDocs/BHT Promo iCloud/Organized AI/Windsurf/openclaw-workshop-infra"

Apply Organized Codebase template:
- Read github.com/Organized-AI/organized-codebase: wire CLAUDE.md, .claude/{skills,commands,agents,hooks}, PLANNING/, ARCHITECTURE/, DOCUMENTATION/, SPECIFICATIONS/, AGENT-HANDOFF/, CONFIG/, scripts/
- Pull relevant skills from github.com/Organized-AI/claude-skills-worth-using and github.com/Organized-AI/plugin-marketplace
- Wire GSD, Ralphy, Boris methodologies
Generate plan file: /Users/supabowl/.claude/plans/organized-gateway-workshop.md

## PHASE 1 — CLOUDFLARE PROVISIONING

wrangler d1 create oc_gateway_db
# Copy the database_id → update wrangler.toml database_id field

wrangler d1 execute oc_gateway_db --file migrations/0001_initial.sql --remote
# Creates 6 tables: attendees, messages, usage_summary, failed_messages, exports, prompt_logs

wrangler queues create oc-messages
wrangler queues create oc-messages-dlq
wrangler r2 bucket create oc-exports

# Set all secrets via wrangler secret put:
# WEBHOOK_SECRET    — Meta webhook verify token (you choose, set same in Meta Console)
# META_ACCESS_TOKEN — WhatsApp Cloud API permanent token (Meta Developer Console)
# META_PHONE_ID     — Phone number ID (Meta Developer Console > WhatsApp > API Setup)
# OPENCLAW_URL      — http://100.82.244.127:18789 (claws-mac-mini Tailscale)
# ADMIN_PHONE       — Jordan's E.164 phone for DLQ alerts
# ENCRYPTION_KEY    — openssl rand -base64 32

## PHASE 2 — WORKER IMPLEMENTATION

npm install hono @hono/zod-validator zod

### src/index.ts — Hono Worker

GET /webhook/whatsapp:
- Read hub.mode, hub.verify_token, hub.challenge
- If mode==="subscribe" AND verify_token===env.WEBHOOK_SECRET → return hub.challenge (200)
- Else return 403

POST /webhook/whatsapp:
1. Read raw body as text
2. Verify X-Hub-Signature-256 via HMAC-SHA256(env.WEBHOOK_SECRET, rawBody) → reject 403 if mismatch
3. Parse WhatsApp Cloud API webhook payload
4. Extract: phone (entry[0].changes[0].value.messages[0].from), body text, message_id
5. Ignore non-message events (status updates) → return 200
6. KV lookup: env.GATEWAY_KV.get(`wa_phone:${phone}`)
   - null → registerUser(phone, env): write KV wa_phone+registered, INSERT attendees, send provisioning DM
   - exists → user_id = phone
7. Push: env.OC_QUEUE.send({ user_id, phone, body, message_id, ts: Date.now() })
8. Return 200 immediately

async queue(batch, env) consumer:
- For each msg: get DO stub via env.USER_DO.idFromName(user_id), call stub.fetch POST /enqueue
- Ack all messages

GET /admin/replay?msg_id: SELECT failed_message, push to queue, UPDATE replayed_at

Provisioning DM text:
"Hi! 👋 Welcome to the OpenClaw Workshop.

Your ID: {phone}

Activate your AI:
!key sk-... (OpenAI/Anthropic/OpenRouter key)

Your key is encrypted at rest."

### src/durable-objects/UserSession.ts

Storage keys: user_id, api_key (encrypted), api_provider, soul_md, agents_md,
oc_session_id, msg_count, tokens_used, last_active, tier, log_buffer[], queue[], last_log_flush

fetch(request):
- POST /enqueue → enqueue(body)
- Return 200

enqueue(message):
- If starts with "!" → handleCommand(message)
- Push {body, message_id, ts, attempts:0} to queue, save storage
- setAlarm(Date.now() + 2000) if not set

alarm():
1. Load queue from storage — if empty check log flush, return
2. Pop queue[0]
3. Load: api_key, soul_md, agents_md, oc_session_id, user_id
4. If no api_key → send DM "Set your API key: !key sk-...", return
5. Decrypt api_key (AES-256-GCM, ENCRYPTION_KEY)
6. start_time = Date.now()
7. POST env.OPENCLAW_URL/v1/chat/completions:
   Authorization: Bearer {api_key}
   X-User-ID: {user_id}, X-Session-ID: {oc_session_id||""}
   Body: {model:"gpt-4o-mini", messages:[{role:system,content:soul_md+"\n\n"+agents_md},{role:user,content:body}]}
8. SUCCESS:
   - Send WhatsApp reply via Meta Send API
   - Update msg_count++, tokens_used+=total_tokens, last_active=now
   - Save oc_session_id from response header if present
   - cost_usd = (prompt_tokens*0.00000015)+(completion_tokens*0.0000006)
   - Append to log_buffer: {id:uuid, user_id, ts, user_message, assistant_reply, model_used, prompt_tokens, completion_tokens, total_tokens, cost_usd, latency_ms:Date.now()-start_time}
   - Remove msg from queue, save
   - If log_buffer>=20 OR now-last_log_flush>10000 → flushLogBuffer()
9. FAILURE attempt 1-2:
   - Increment attempts, push back to front of queue, save
   - If attempts===2 → DM user "Still processing, hang tight..."
   - setAlarm(attempts===1 ? 30000 : 60000)
10. FAILURE attempt>=3:
    - INSERT failed_messages, DM user "Something went wrong, Jordan notified"
    - DM env.ADMIN_PHONE "❌ DLQ: {user_id} | {body.slice(0,100)}"
    - Remove from queue, save
11. If queue not empty → setAlarm(Date.now() + 2000)

flushLogBuffer():
- Batch INSERT into D1 prompt_logs
- UPDATE usage_summary
- Clear log_buffer, update last_log_flush

handleCommand(text):
!key {val}   → encrypt + store api_key, detect provider, save hash to D1, reply "✓ API key saved"
!soul {val}  → store soul_md, reply "✓ SOUL.md updated"
!agents {val}→ store agents_md, reply "✓ AGENTS.md updated"
!status      → reply queue/tokens/count/tier summary
!clear       → set oc_session_id=null, reply "✓ Session cleared"
!good        → UPDATE prompt_logs SET user_feedback='good' WHERE user_id=? latest ts
!bad         → UPDATE prompt_logs SET user_feedback='weak' ...
!pin         → UPDATE prompt_logs SET ft_candidate=1 ...
!export      → INSERT exports row, KV write, DM "Building export..."
unknown      → enqueue() as regular message

sendWhatsApp(to, text, env):
POST https://graph.facebook.com/v19.0/{env.META_PHONE_ID}/messages
Authorization: Bearer {env.META_ACCESS_TOKEN}
{messaging_product:"whatsapp", to, type:"text", text:{body:text}}

encryptKey / decryptKey:
AES-256-GCM via Web Crypto API, key = SHA-256(env.ENCRYPTION_KEY), store as base64(iv):base64(ct)

Default SOUL.md (load into new DO on first message):
"You are an OpenClaw AI assistant helping workshop attendees at the Organized AI OpenClaw Part 1 event. You are knowledgeable about OpenClaw architecture, AI harness engineering, GTM/marketing technology, and AI automation. Be direct and practical. Host: Jordan Hill, organizedai.vip. Keep responses concise for WhatsApp — under 400 characters, use line breaks."

Default AGENTS.md:
"OpenClaw workshop session. User may ask: architecture concepts, GTM tracking, marketing tech, AI agent setup. Docs: guide.organizedai.vip, wiki.organizedai.vip. Event: lu.ma/1l21y2zh"

## PHASE 3 — OPENCLAW CONFIG (on claws-mac-mini)

ssh claws
# Edit ~/.openclaw/openclaw.json — enable WhatsApp adapter, ensure ExoClaw bridge active on port 18789
# Test: curl -X POST http://127.0.0.1:18789/v1/chat/completions -H "Authorization: Bearer {key}" -H "Content-Type: application/json" -d '{"model":"gpt-4o-mini","messages":[{"role":"user","content":"say hi"}]}'

## PHASE 4 — ONBOARDING TEST

1. wrangler deploy
2. Set webhook in Meta Developer Console:
   URL: https://organized-gateway.workers.dev/webhook/whatsapp
   Verify token: (your WEBHOOK_SECRET value)
   Subscribe to: messages
3. Test full flow with your phone — verify provisioning DM, !key, first message, D1 rows
4. Test with 3 different phones
5. QR code URL: wa.me/{PHONE_NUMBER_E164}?text=Hi%20OpenClaw%20workshop!

## REPO / INFRA DETAILS

GitHub: github.com/Organized-AI/openclaw-workshop-infra
CF Account: 691fe25d377abac03627d6a88d3eeac9
GATEWAY_KV ID: 104c355b4c504bc6a8fafd846034e35f
OpenClaw: claws-mac-mini, 100.82.244.127 (Tailscale), ssh claws
Local path: /Users/supabowl/Library/Mobile Documents/com~apple~CloudDocs/BHT Promo iCloud/Organized AI/Windsurf/openclaw-workshop-infra
Schema: migrations/0001_initial.sql
Architecture: docs/openclaw-gateway-hybrid-v2.html

## SUCCESS CRITERIA

Phase 1: d1/queues/r2 created, 6 secrets set, migration ran (6 tables in D1)
Phase 2: wrangler deploy succeeds, TS compiles clean, webhook verify works
Phase 4: provisioning DM received, !key works, first AI reply received in WhatsApp, D1 prompt_logs has rows
