CREATE TABLE career_nodes (
    id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES users(id),name text NOT NULL,description text NOT NULL DEFAULT '',
    badge_key text NOT NULL,parent_career_id uuid,sort_order integer NOT NULL DEFAULT 0,
    conditions_json jsonb NOT NULL,version integer NOT NULL DEFAULT 1,create_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),UNIQUE(id,user_id),
    FOREIGN KEY(parent_career_id,user_id) REFERENCES career_nodes(id,user_id),CHECK(parent_career_id IS NULL OR parent_career_id<>id)
);
CREATE TABLE titles (
    id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES users(id),name text NOT NULL,description text NOT NULL DEFAULT '',
    icon_key text NOT NULL,conditions_json jsonb NOT NULL,version integer NOT NULL DEFAULT 1,create_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),updated_at timestamptz NOT NULL DEFAULT now(),UNIQUE(id,user_id)
);
CREATE TABLE achievement_references (
    entity_type text NOT NULL CHECK(entity_type IN ('career','title')),entity_id uuid NOT NULL,user_id uuid NOT NULL,
    reference_type text NOT NULL CHECK(reference_type IN ('skill','task')),reference_id uuid NOT NULL,skill_id uuid,task_id uuid,
    PRIMARY KEY(entity_type,entity_id,reference_type,reference_id),
    CHECK((reference_type='skill' AND skill_id=reference_id AND task_id IS NULL) OR (reference_type='task' AND task_id=reference_id AND skill_id IS NULL)),
    FOREIGN KEY(skill_id,user_id) REFERENCES skills(id,user_id),FOREIGN KEY(task_id,user_id) REFERENCES tasks(id,user_id)
);
CREATE TABLE career_transitions (
    id uuid PRIMARY KEY,user_id uuid NOT NULL,from_career_id uuid,to_career_id uuid NOT NULL,
    conditions_snapshot jsonb NOT NULL,evidence_snapshot jsonb NOT NULL,confirmed_at timestamptz NOT NULL DEFAULT now(),
    FOREIGN KEY(from_career_id,user_id) REFERENCES career_nodes(id,user_id),FOREIGN KEY(to_career_id,user_id) REFERENCES career_nodes(id,user_id)
);
CREATE INDEX career_history ON career_transitions(user_id,confirmed_at,id);
CREATE TABLE user_titles (
    user_id uuid NOT NULL,title_id uuid NOT NULL,unlocked_at timestamptz NOT NULL DEFAULT now(),equipped_at timestamptz,
    conditions_snapshot jsonb NOT NULL,evidence_snapshot jsonb NOT NULL,PRIMARY KEY(user_id,title_id),
    FOREIGN KEY(title_id,user_id) REFERENCES titles(id,user_id)
);
CREATE UNIQUE INDEX title_one_equipped ON user_titles(user_id) WHERE equipped_at IS NOT NULL;
CREATE TABLE achievement_profiles (
    user_id uuid PRIMARY KEY REFERENCES users(id),current_career_id uuid,equipped_title_id uuid,
    FOREIGN KEY(current_career_id,user_id) REFERENCES career_nodes(id,user_id),FOREIGN KEY(equipped_title_id,user_id) REFERENCES titles(id,user_id)
);
CREATE TABLE achievement_commands (
    id uuid PRIMARY KEY,user_id uuid NOT NULL REFERENCES users(id),kind text NOT NULL,target_id uuid,
    request_hash text NOT NULL,result_json jsonb NOT NULL,created_at timestamptz NOT NULL DEFAULT now()
);
