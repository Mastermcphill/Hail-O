CREATE TABLE IF NOT EXISTS billing_invoices (
  id UUID PRIMARY KEY,
  org_id TEXT NOT NULL,
  purchase_id UUID REFERENCES marketplace_purchases(id) ON DELETE SET NULL,
  provider TEXT NOT NULL,
  provider_invoice_id TEXT,
  currency TEXT NOT NULL,
  subtotal_minor BIGINT NOT NULL DEFAULT 0,
  discount_minor BIGINT NOT NULL DEFAULT 0,
  credit_applied_minor BIGINT NOT NULL DEFAULT 0,
  total_due_minor BIGINT NOT NULL DEFAULT 0,
  status TEXT NOT NULL CHECK (
    status IN ('draft', 'open', 'paid', 'failed', 'void', 'refunded')
  ),
  period_start TIMESTAMPTZ NOT NULL,
  period_end TIMESTAMPTZ NOT NULL,
  due_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_billing_invoices_org_created_desc
ON billing_invoices(org_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_billing_invoices_purchase_created_desc
ON billing_invoices(purchase_id, created_at DESC);

CREATE TABLE IF NOT EXISTS dunning_cases (
  id UUID PRIMARY KEY,
  org_id TEXT NOT NULL,
  purchase_id UUID REFERENCES marketplace_purchases(id) ON DELETE SET NULL,
  invoice_id UUID NOT NULL REFERENCES billing_invoices(id) ON DELETE CASCADE,
  state TEXT NOT NULL CHECK (
    state IN ('active', 'recovered', 'canceled', 'written_off', 'paused')
  ),
  attempt_count INTEGER NOT NULL DEFAULT 0,
  next_attempt_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_dunning_cases_state_next
ON dunning_cases(state, next_attempt_at, updated_at DESC);

CREATE TABLE IF NOT EXISTS dunning_attempts (
  id UUID PRIMARY KEY,
  case_id UUID NOT NULL REFERENCES dunning_cases(id) ON DELETE CASCADE,
  attempt_no INTEGER NOT NULL,
  attempted_at TIMESTAMPTZ NOT NULL,
  outcome TEXT NOT NULL CHECK (outcome IN ('success', 'fail', 'skipped')),
  provider_ref TEXT,
  error_code TEXT,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_dunning_attempts_case_attempt
ON dunning_attempts(case_id, attempt_no DESC, attempted_at DESC);

CREATE TABLE IF NOT EXISTS comms_templates (
  id TEXT PRIMARY KEY,
  channel TEXT NOT NULL CHECK (channel IN ('email', 'sms', 'push')),
  subject TEXT,
  body TEXT NOT NULL,
  vars_schema JSONB NOT NULL DEFAULT '{}'::jsonb,
  is_active BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE TABLE IF NOT EXISTS comms_outbox (
  id UUID PRIMARY KEY,
  channel TEXT NOT NULL CHECK (channel IN ('email', 'sms', 'push')),
  recipient TEXT NOT NULL,
  template_id TEXT NOT NULL REFERENCES comms_templates(id) ON DELETE RESTRICT,
  payload_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  status TEXT NOT NULL CHECK (status IN ('queued', 'sent', 'failed', 'dead')),
  attempts INTEGER NOT NULL DEFAULT 0,
  next_retry_at TIMESTAMPTZ,
  dedupe_key TEXT NOT NULL UNIQUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_comms_outbox_status_retry
ON comms_outbox(status, next_retry_at, updated_at DESC);

INSERT INTO comms_templates(id, channel, subject, body, vars_schema, is_active)
VALUES
  (
    'invoice_failed_1',
    'email',
    'Action needed: invoice payment failed',
    'Your invoice payment failed. Please retry your payment method.',
    '{"org_name":"string","invoice_id":"string"}'::jsonb,
    TRUE
  ),
  (
    'invoice_failed_2',
    'email',
    'Reminder: invoice still unpaid',
    'Your invoice is still unpaid. Service restrictions may apply soon.',
    '{"org_name":"string","invoice_id":"string"}'::jsonb,
    TRUE
  ),
  (
    'invoice_failed_final',
    'email',
    'Final notice before service restriction',
    'Please settle your invoice immediately to avoid service restrictions.',
    '{"org_name":"string","invoice_id":"string"}'::jsonb,
    TRUE
  ),
  (
    'payment_recovered',
    'email',
    'Payment recovered successfully',
    'Thank you. Your subscription payment has been recovered.',
    '{"org_name":"string","invoice_id":"string"}'::jsonb,
    TRUE
  ),
  (
    'trial_ending',
    'email',
    'Trial ending soon',
    'Your trial is ending soon. Add a payment method to continue.',
    '{"org_name":"string"}'::jsonb,
    TRUE
  ),
  (
    'subscription_canceled',
    'email',
    'Subscription canceled',
    'Your subscription has been canceled.',
    '{"org_name":"string"}'::jsonb,
    TRUE
  )
ON CONFLICT (id) DO UPDATE
SET
  channel = EXCLUDED.channel,
  subject = EXCLUDED.subject,
  body = EXCLUDED.body,
  vars_schema = EXCLUDED.vars_schema,
  is_active = EXCLUDED.is_active;
