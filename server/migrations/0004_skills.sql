CREATE TABLE skill_trees (
    id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id),
    name text NOT NULL, description text NOT NULL DEFAULT '', theme_key text NOT NULL DEFAULT 'blue',
    sort_order integer NOT NULL DEFAULT 0, archived_at timestamptz,
    version integer NOT NULL DEFAULT 1 CHECK(version>0),
    create_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(id,user_id)
);
CREATE INDEX tree_owner ON skill_trees(user_id,sort_order,id);
CREATE TABLE skills (
    id uuid PRIMARY KEY, user_id uuid NOT NULL REFERENCES users(id),
    tree_id uuid NOT NULL, parent_skill_id uuid,
    name text NOT NULL, description text NOT NULL DEFAULT '', icon_key text NOT NULL DEFAULT 'star',
    sort_order integer NOT NULL DEFAULT 0, archived_at timestamptz,
    version integer NOT NULL DEFAULT 1 CHECK(version>0), create_hash text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(), updated_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(id,user_id), UNIQUE(id,user_id,tree_id),
    FOREIGN KEY(tree_id,user_id) REFERENCES skill_trees(id,user_id),
    FOREIGN KEY(parent_skill_id,user_id,tree_id) REFERENCES skills(id,user_id,tree_id),
    CHECK(parent_skill_id IS NULL OR parent_skill_id<>id)
);
CREATE INDEX skill_owner ON skills(user_id,tree_id,sort_order,id);
CREATE INDEX skill_parent ON skills(parent_skill_id);
