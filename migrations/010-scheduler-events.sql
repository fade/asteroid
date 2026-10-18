-- Migration 010: Scheduler Events Table
-- Description: Record each scheduler enable/disable with who did it and what was on air

CREATE TABLE IF NOT EXISTS scheduler_events (
    _id SERIAL PRIMARY KEY,
    event VARCHAR(16) NOT NULL CHECK (event IN ('enabled', 'disabled')),
    actor VARCHAR(255),
    playlist VARCHAR(255),
    track TEXT,
    loaded_playlist VARCHAR(255),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_scheduler_events_created_at ON scheduler_events(created_at);

-- Grant permissions
GRANT ALL PRIVILEGES ON scheduler_events TO asteroid;
GRANT ALL PRIVILEGES ON scheduler_events__id_seq TO asteroid;

DO $$
BEGIN
    RAISE NOTICE 'Migration 010: Scheduler events table created successfully!';
END $$;
