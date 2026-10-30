CREATE TABLE skill_links (
    id uuid PRIMARY KEY,user_id uuid NOT NULL,from_skill_id uuid NOT NULL,to_skill_id uuid NOT NULL,
    link_type text NOT NULL CHECK(link_type IN ('prerequisite','reference')),required_level bigint,
    version integer NOT NULL DEFAULT 1,create_hash text NOT NULL,created_at timestamptz NOT NULL DEFAULT now(),deleted_at timestamptz,
    CHECK(from_skill_id<>to_skill_id),
    CHECK((link_type='reference' AND required_level IS NULL) OR (link_type='prerequisite' AND required_level BETWEEN 1 AND 1000000)),
    FOREIGN KEY(from_skill_id,user_id) REFERENCES skills(id,user_id),
    FOREIGN KEY(to_skill_id,user_id) REFERENCES skills(id,user_id)
);
CREATE UNIQUE INDEX link_active_unique ON skill_links(from_skill_id,to_skill_id,link_type) WHERE deleted_at IS NULL;
CREATE INDEX link_source ON skill_links(user_id,from_skill_id) WHERE deleted_at IS NULL;
CREATE INDEX link_target ON skill_links(user_id,to_skill_id) WHERE deleted_at IS NULL;
