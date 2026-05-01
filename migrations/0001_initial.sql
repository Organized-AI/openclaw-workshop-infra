-- oc_gateway_db — initial schema
-- Run: wrangler d1 execute oc_gateway_db --file migrations/0001_initial.sql

CREATE TABLE IF NOT EXISTS attendees (
  user_id         TEXT PRIMARY KEY,  -- E.164 phone number
  wa_phone        TEXT UNIQUE NOT NULL,
  display_name    TEXT,
  tier            TEXT DEFAULT 'workshop',
  api_key_hash    TEXT,              -- SHA-256 of BYOK key
  api_provider    TEXT,              -- openai|anthropic|openrouter
  registered_at   INTEGER NOT NULL,  -- unix ms
  breakaway_at    INTEGER            -- null until export requested
);

CREATE TABLE IF NOT EXISTS messages (
  id              TEXT PRIMARY KEY,  -- Meta message_id or UUID
  user_id         TEXT NOT NULL REFERENCES attendees(user_id),
  direction       TEXT NOT NULL,     -- 'inbound' | 'outbound'
  content         TEXT NOT NULL,
  model           TEXT,
  tokens_used     INTEGER,
  oc_session_id   TEXT,
  ts              INTEGER NOT NULL
);
CREATE INDEX idx_messages_user_ts ON messages(user_id, ts);

CREATE TABLE IF NOT EXISTS usage_summary (
  user_id          TEXT PRIMARY KEY REFERENCES attendees(user_id),
  total_messages   INTEGER DEFAULT 0,
  total_tokens     INTEGER DEFAULT 0,
  first_message_at INTEGER,
  last_message_at  INTEGER
);

CREATE TABLE IF NOT EXISTS failed_messages (
  id            TEXT PRIMARY KEY,
  user_id       TEXT NOT NULL REFERENCES attendees(user_id),
  original_body TEXT NOT NULL,
  attempts      INTEGER DEFAULT 0,
  last_error    TEXT,
  failed_at     INTEGER NOT NULL,
  replayed_at   INTEGER
);

CREATE TABLE IF NOT EXISTS exports (
  export_id    TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES attendees(user_id),
  requested_at INTEGER NOT NULL,
  status       TEXT DEFAULT 'pending', -- pending|building|ready|delivered
  r2_key       TEXT,
  signed_url   TEXT,
  delivered_at INTEGER
);

-- Token observability + routing analysis + fine-tuning dataset
CREATE TABLE IF NOT EXISTS prompt_logs (
  id                  TEXT PRIMARY KEY,
  user_id             TEXT NOT NULL REFERENCES attendees(user_id),
  session_id          TEXT,
  ts                  INTEGER NOT NULL,

  -- Prompt capture (fine-tuning + conversation export)
  system_prompt       TEXT,  -- SOUL.md + AGENTS.md snapshot per turn
  user_message        TEXT,
  assistant_reply     TEXT,

  -- Routing record (UncommonRoute analysis)
  model_requested     TEXT,
  model_used          TEXT,
  difficulty_tier     TEXT,  -- SIMPLE|MEDIUM|COMPLEX
  difficulty_score    REAL,  -- 0.0–1.0
  routing_mode        TEXT,  -- auto|fast|best

  -- Token observability (CodeBurn)
  prompt_tokens       INTEGER,
  completion_tokens   INTEGER,
  cache_read_tokens   INTEGER,
  cache_write_tokens  INTEGER,
  total_tokens        INTEGER,
  cost_usd            REAL,

  -- Tool tracking (CodeBurn task classifier)
  tool_calls_json     TEXT,  -- JSON array [{name, input, output}]
  task_category       TEXT,  -- Coding|Debugging|Exploration|Planning|…
  latency_ms          INTEGER,

  -- Quality signals (feedback + fine-tuning flags)
  user_feedback       TEXT,  -- 'good'|'weak'|'strong'|null
  retry_count         INTEGER DEFAULT 0,
  ft_candidate        INTEGER DEFAULT 0,  -- 1 = include in FT export
  ft_exported_at      INTEGER
);

CREATE INDEX idx_prompt_logs_user_ts ON prompt_logs(user_id, ts);
CREATE INDEX idx_prompt_logs_model   ON prompt_logs(model_used, ts);
CREATE INDEX idx_prompt_logs_ft      ON prompt_logs(ft_candidate) WHERE ft_candidate = 1;
CREATE INDEX idx_prompt_logs_tier    ON prompt_logs(user_id, difficulty_tier);
