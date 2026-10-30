CREATE TABLE task_attempts (
    id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES users(id),task_id uuid NOT NULL,
    attempt_no integer NOT NULL CHECK(attempt_no>0),result text NOT NULL CHECK(result IN ('success','failed')),
    reason text NOT NULL DEFAULT '',concluded_at timestamptz NOT NULL DEFAULT now(),reversed_at timestamptz,
    request_hash text NOT NULL,result_json jsonb NOT NULL DEFAULT '{}',
    UNIQUE(id,user_id),UNIQUE(task_id,attempt_no),
    FOREIGN KEY(task_id,user_id) REFERENCES tasks(id,user_id)
);
CREATE INDEX attempt_history ON task_attempts(user_id,concluded_at DESC,id DESC);
CREATE TABLE task_attempt_skills (
    attempt_id uuid NOT NULL,user_id uuid NOT NULL,skill_id uuid NOT NULL,reward_levels bigint NOT NULL CHECK(reward_levels>=0),
    PRIMARY KEY(attempt_id,skill_id),
    FOREIGN KEY(attempt_id,user_id) REFERENCES task_attempts(id,user_id),
    FOREIGN KEY(skill_id,user_id) REFERENCES skills(id,user_id)
);
CREATE INDEX attempt_skill_history ON task_attempt_skills(user_id,skill_id,attempt_id);
CREATE TABLE task_rewards (
    id uuid PRIMARY KEY,user_id uuid NOT NULL,attempt_id uuid NOT NULL,skill_id uuid NOT NULL,
    reward_levels_snapshot bigint NOT NULL CHECK(reward_levels_snapshot>=0),xp_amount bigint NOT NULL CHECK(xp_amount>=0),
    growth_event_id uuid NOT NULL REFERENCES growth_events(id),created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(attempt_id,skill_id),
    FOREIGN KEY(attempt_id,user_id) REFERENCES task_attempts(id,user_id),
    FOREIGN KEY(skill_id,user_id) REFERENCES skills(id,user_id)
);
