/**
 * organized-gateway — Cloudflare Worker
 *
 * Hybrid architecture: CF Queue + Durable Objects
 * Handles: WhatsApp webhook ingress, user provisioning,
 *          queue push, consumer routing, DO drain to OpenClaw
 *
 * Build via Claude Code using PLANNING/claude-code-prompt.md
 */

import { UserSession } from './durable-objects/UserSession';

export { UserSession };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    // WhatsApp webhook
    if (url.pathname === '/webhook/whatsapp') {
      if (request.method === 'GET') return handleWebhookVerify(request, env);
      if (request.method === 'POST') return handleWebhookMessage(request, env);
    }

    // Admin replay endpoint
    if (url.pathname.startsWith('/admin/replay')) {
      return handleAdminReplay(request, env);
    }

    return new Response('organized-gateway v1', { status: 200 });
  },

  async queue(batch: MessageBatch<QueueMessage>, env: Env): Promise<void> {
    for (const msg of batch.messages) {
      const { user_id } = msg.body;
      const id = env.USER_DO.idFromName(user_id);
      const stub = env.USER_DO.get(id);
      await stub.enqueue(msg.body);
      msg.ack();
    }
  },
};

// ── Stubs — implement in Phase 2 ──
async function handleWebhookVerify(req: Request, env: Env): Promise<Response> {
  // TODO: verify token handshake
  return new Response('stub', { status: 200 });
}

async function handleWebhookMessage(req: Request, env: Env): Promise<Response> {
  // TODO: verify signature, KV lookup, queue push, registration DM
  return new Response(null, { status: 200 });
}

async function handleAdminReplay(req: Request, env: Env): Promise<Response> {
  // TODO: DLQ replay by message ID
  return new Response('stub', { status: 200 });
}

interface QueueMessage {
  user_id: string;
  phone: string;
  body: string;
  message_id: string;
}

interface Env {
  GATEWAY_KV: KVNamespace;
  OC_DB: D1Database;
  OC_QUEUE: Queue<QueueMessage>;
  USER_DO: DurableObjectNamespace;
  OC_EXPORTS: R2Bucket;
  WEBHOOK_SECRET: string;
  OPENCLAW_URL: string;
  META_ACCESS_TOKEN: string;
  META_PHONE_ID: string;
  ADMIN_PHONE: string;
  ENCRYPTION_KEY: string;
}
