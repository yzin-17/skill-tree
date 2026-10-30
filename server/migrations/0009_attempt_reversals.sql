CREATE TABLE task_reversals (
    id uuid PRIMARY KEY,user_id uuid NOT NULL,attempt_id uuid NOT NULL UNIQUE,
    reason text NOT NULL DEFAULT '',request_hash text NOT NULL,result_json jsonb NOT NULL DEFAULT '{}',
    created_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY(attempt_id,user_id) REFERENCES task_attempts(id,user_id)
);
CREATE UNIQUE INDEX growth_single_reversal ON growth_events(reverses_event_id) WHERE reverses_event_id IS NOT NULL;
