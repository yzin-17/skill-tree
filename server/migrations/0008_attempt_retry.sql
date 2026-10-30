CREATE TABLE task_retry_requests (
    id uuid PRIMARY KEY,user_id uuid NOT NULL,task_id uuid NOT NULL,
    previous_attempt_no integer NOT NULL,next_attempt_no integer NOT NULL,
    request_hash text NOT NULL,result_json jsonb NOT NULL DEFAULT '{}',created_at timestamptz NOT NULL DEFAULT now(),
    UNIQUE(task_id,previous_attempt_no),
    FOREIGN KEY(task_id,user_id) REFERENCES tasks(id,user_id)
);
CREATE INDEX retry_history ON task_retry_requests(user_id,created_at,id);
