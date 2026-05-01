/**
 * UserSession Durable Object
 *
 * One instance per phone number (user_id).
 * Owns: per-user queue, SOUL.md, AGENTS.md, BYOK api_key,
 *       session state, alarm-based drain to OpenClaw,
 *       log_buffer batch flush to D1, prompt_logs recording.
 *
 * Build via Claude Code using PLANNING/claude-code-prompt.md
 */

export class UserSession implements DurableObject {
  state: DurableObjectState;
  env: any;

  constructor(state: DurableObjectState, env: any) {
    this.state = state;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    const { action, message } = await request.json() as any;
    if (action === 'enqueue') await this.enqueue(message);
    return new Response('ok');
  }

  async enqueue(message: any): Promise<void> {
    // TODO: push to queue, schedule alarm if not set
  }

  async alarm(): Promise<void> {
    // TODO: drain one message to OpenClaw, log to D1, reschedule
  }
}
