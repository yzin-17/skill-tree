CREATE TABLE activity_events (
    id uuid PRIMARY KEY,
    user_id uuid NOT NULL REFERENCES users(id),
    type text NOT NULL,
    producer text NOT NULL CHECK(producer IN ('server','client')),
    entity_type text NOT NULL,
    entity_id uuid NOT NULL,
    source_key text NOT NULL,
    summary text NOT NULL,
    skill_ids uuid[] NOT NULL DEFAULT '{}',
    metadata jsonb NOT NULL DEFAULT '{}',
    occurred_at timestamptz NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(user_id,source_key)
);
CREATE INDEX activity_timeline ON activity_events(user_id,occurred_at DESC,id DESC);
CREATE INDEX activity_entity ON activity_events(entity_type,entity_id,user_id);
CREATE INDEX activity_skills ON activity_events USING gin(skill_ids);
