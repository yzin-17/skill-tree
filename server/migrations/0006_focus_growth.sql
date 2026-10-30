CREATE TABLE focus_sessions (
    id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES users(id),skill_id uuid NOT NULL,task_id uuid,
    mode text NOT NULL CHECK(mode IN ('count_up','countdown','pomodoro','manual')),target_seconds bigint,
    effective_seconds bigint NOT NULL CHECK(effective_seconds>=0),started_at timestamptz NOT NULL,ended_at timestamptz NOT NULL,
    note text NOT NULL DEFAULT '',source text NOT NULL CHECK(source IN ('timer','manual')),pomodoro_rounds integer NOT NULL DEFAULT 0,
    version integer NOT NULL DEFAULT 1,created_at timestamptz NOT NULL DEFAULT now(),invalidated_at timestamptz,
    clock_adjusted boolean NOT NULL DEFAULT false,create_hash text NOT NULL,awarded_xp bigint NOT NULL,
    settled_progress jsonb NOT NULL DEFAULT '{}',
    UNIQUE(id,user_id),
    FOREIGN KEY(skill_id,user_id) REFERENCES skills(id,user_id),
    FOREIGN KEY(task_id,user_id) REFERENCES tasks(id,user_id)
);
CREATE INDEX focus_history ON focus_sessions(user_id,ended_at DESC,id DESC);
CREATE INDEX focus_skill ON focus_sessions(user_id,skill_id);
CREATE INDEX focus_task ON focus_sessions(user_id,task_id);
CREATE TABLE growth_events (
    id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES users(id),skill_id uuid NOT NULL,
    event_type text NOT NULL CHECK(event_type IN ('focus_accrual','task_success','reversal')),
    source_id uuid NOT NULL,delta_xp bigint NOT NULL,note text NOT NULL DEFAULT '',created_at timestamptz NOT NULL DEFAULT now(),
    reverses_event_id uuid REFERENCES growth_events(id),
    UNIQUE(user_id,skill_id,event_type,source_id),
    FOREIGN KEY(skill_id,user_id) REFERENCES skills(id,user_id)
);
CREATE INDEX growth_skill ON growth_events(user_id,skill_id,created_at,id);
