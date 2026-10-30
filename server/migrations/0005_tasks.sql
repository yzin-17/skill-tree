CREATE TABLE tasks (
    id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id),
    title text NOT NULL, description text NOT NULL DEFAULT '', success_criteria text NOT NULL DEFAULT '',
    status text NOT NULL CHECK(status IN ('todo','in_progress','success','failed','canceled')),
    due_at timestamptz, pinned boolean NOT NULL DEFAULT false,
    current_attempt_no integer NOT NULL DEFAULT 1 CHECK(current_attempt_no>0),
    version integer NOT NULL DEFAULT 1 CHECK(version>0), create_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(id,user_id)
);
CREATE INDEX task_owner ON tasks(user_id,status,pinned,due_at);
CREATE TABLE task_skills (
    task_id uuid NOT NULL,skill_id uuid NOT NULL,user_id uuid NOT NULL,
    reward_levels bigint NOT NULL CHECK(reward_levels>=0 AND reward_levels<=1000000),
    created_at timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY(task_id,skill_id),
    FOREIGN KEY(task_id,user_id) REFERENCES tasks(id,user_id),
    FOREIGN KEY(skill_id,user_id) REFERENCES skills(id,user_id)
);
CREATE INDEX task_skill_reverse ON task_skills(skill_id,task_id);
