-- Asteroid Radio Database Initialization Script
-- PostgreSQL Schema for persistent storage

-- Enable UUID extension for generating unique IDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table
CREATE TABLE IF NOT EXISTS "USERS" (
    _id SERIAL PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    "password-hash" TEXT NOT NULL,
    role VARCHAR(50) DEFAULT 'listener',
    active integer DEFAULT 1,
    "created-date" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "last-login" TIMESTAMP,
    avatar_path TEXT,
    CONSTRAINT valid_role CHECK (role IN ('listener', 'dj', 'admin'))
);

-- Create index on username and email for faster lookups
CREATE INDEX idx_users_username ON "USERS"(username);
CREATE INDEX idx_users_email ON "USERS"(email);

-- Tracks table
CREATE TABLE IF NOT EXISTS tracks (
    _id SERIAL PRIMARY KEY,
    title VARCHAR(500) NOT NULL,
    artist VARCHAR(500),
    album VARCHAR(500),
    duration INTEGER DEFAULT 0,
    format VARCHAR(50),
    bitrate integer,
    "file-path" TEXT NOT NULL UNIQUE,
    "play-count" INTEGER DEFAULT 0,
    "added-date" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "last-played" TIMESTAMP
);

-- Create indexes for common queries
CREATE INDEX idx_tracks_artist ON tracks(artist);
CREATE INDEX idx_tracks_album ON tracks(album);
CREATE INDEX idx_tracks_title ON tracks(title);

-- Playlists table
CREATE TABLE IF NOT EXISTS playlists (
    _id SERIAL PRIMARY KEY,
    "user-id" INTEGER NOT NULL REFERENCES "USERS"(_id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    description TEXT,
    "created-date" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "modified-date" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create index on user_id for faster user playlist lookups
CREATE INDEX idx_playlists_user_id ON playlists("user-id");

-- Playlist tracks junction table (many-to-many relationship)
CREATE TABLE IF NOT EXISTS playlist_tracks (
    _id SERIAL PRIMARY KEY,
    playlist_id INTEGER NOT NULL REFERENCES playlists(_id) ON DELETE CASCADE,
    track_id INTEGER NOT NULL REFERENCES tracks(_id) ON DELETE CASCADE,
    position INTEGER NOT NULL,
    added_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE(playlist_id, track_id, "position")
);

-- Create indexes for playlist track queries
CREATE INDEX idx_playlist_tracks_playlist_id ON playlist_tracks(playlist_id);
CREATE INDEX idx_playlist_tracks_track_id ON playlist_tracks(track_id);

-- Sessions table (for Radiance session management)
-- CREATE TABLE IF NOT EXISTS sessions (
--     _id VARCHAR(255) PRIMARY KEY,
--     "user_id INTEGER REFERENCES users(id) ON DELETE CASCADE,
--     data JSONB,
--     created_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
--     expires_at TIMESTAMP NOT NULL
-- );

-- Create index on user_id and expires_at
-- CREATE INDEX idx_sessions_user_id ON sessions(user_id);
-- CREATE INDEX idx_sessions_expires_at ON sessions(expires_at);

-- Listener snapshots table
CREATE TABLE IF NOT EXISTS listener_snapshots (
    _id SERIAL PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    mount VARCHAR(100) NOT NULL,
    listener_count INTEGER NOT NULL DEFAULT 0
);

-- Create indexes for user snapshot queries
CREATE INDEX idx_snapshots_timestamp ON listener_snapshots(timestamp);
CREATE INDEX idx_snapshots_mount ON listener_snapshots(mount);

-- Listener sessions: individual connection records (privacy-safe)
CREATE TABLE IF NOT EXISTS listener_sessions (
    _id SERIAL PRIMARY KEY,
    session_id VARCHAR(64) UNIQUE NOT NULL,
    session_start TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    session_end TIMESTAMP,
    ip_hash VARCHAR(64) NOT NULL,  -- SHA256 hash, not reversible
    country_code VARCHAR(2),
    city VARCHAR(100),
    region VARCHAR(100),
    user_agent TEXT,
    mount VARCHAR(100) NOT NULL,
    duration_seconds INTEGER,
    user_id INTEGER REFERENCES "USERS"(_id) ON DELETE SET NULL  -- Optional link to registered user
);

-- Create indexes for listener sessions queries
CREATE INDEX idx_sessions_start ON listener_sessions(session_start);
CREATE INDEX idx_sessions_ip_hash ON listener_sessions(ip_hash);
CREATE INDEX idx_sessions_country ON listener_sessions(country_code);
CREATE INDEX idx_sessions_user ON listener_sessions(user_id);

-- Daily aggregated statistics (for efficient dashboard queries)
CREATE TABLE IF NOT EXISTS listener_daily_stats (
    _id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    mount VARCHAR(100) NOT NULL,
    unique_listeners INTEGER DEFAULT 0,
    peak_concurrent INTEGER DEFAULT 0,
    total_listen_minutes INTEGER DEFAULT 0,
    new_listeners INTEGER DEFAULT 0,
    returning_listeners INTEGER DEFAULT 0,
    avg_session_minutes DECIMAL(10,2),
    UNIQUE(date, mount)
);

-- Create indexes for listener daily stats queries
CREATE INDEX idx_daily_stats_date ON listener_daily_stats(date);

-- Hourly breakdown for time-of-day analysis
CREATE TABLE IF NOT EXISTS listener_hourly_stats (
    _id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    hour INTEGER NOT NULL CHECK (hour >= 0 AND hour <= 23),
    mount VARCHAR(100) NOT NULL,
    unique_listeners INTEGER DEFAULT 0,
    peak_concurrent INTEGER DEFAULT 0,
    UNIQUE(date, hour, mount)
);

-- Create indexes for listener hourly stats queries
CREATE INDEX idx_hourly_stats_date ON listener_hourly_stats(date);

-- Geographic aggregates
CREATE TABLE IF NOT EXISTS listener_geo_stats (
    _id SERIAL PRIMARY KEY,
    date DATE NOT NULL,
    country_code VARCHAR(2) NOT NULL,
    city VARCHAR(100),
    listener_count INTEGER DEFAULT 0,
    listen_minutes INTEGER DEFAULT 0,
    UNIQUE(date, country_code, city)
);

-- Create indexes for listener geo stats queries
CREATE INDEX idx_geo_stats_date ON listener_geo_stats(date);
CREATE INDEX idx_geo_stats_country ON listener_geo_stats(country_code);

-- Table for playlist schedules
CREATE TABLE IF NOT EXISTS playlist_schedule (
    _id SERIAL PRIMARY KEY,
    hour INTEGER NOT NULL UNIQUE CHECK (hour >= 0 AND hour <= 23),
    playlist VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- User favorites table - tracks that users have liked/rated
CREATE TABLE IF NOT EXISTS user_favorites (
    _id SERIAL PRIMARY KEY,
    "user-id" INTEGER NOT NULL REFERENCES "USERS"(_id) ON DELETE CASCADE,
    "track-id" INTEGER,  -- Optional: references tracks(_id) when available
    track_title TEXT,    -- Store title directly for title-based favorites
    rating INTEGER DEFAULT 1 CHECK (rating >= 1 AND rating <= 5),
    "created-date" TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_user_favorites_user_id ON user_favorites("user-id");
CREATE INDEX IF NOT EXISTS idx_user_favorites_track_id ON user_favorites("track-id");
CREATE INDEX IF NOT EXISTS idx_user_favorites_rating ON user_favorites(rating);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_favorites_unique ON user_favorites("user-id", COALESCE(track_title, ''));

-- User listening history - per-user track play history
CREATE TABLE IF NOT EXISTS listening_history (
    _id SERIAL PRIMARY KEY,
    "user-id" INTEGER NOT NULL REFERENCES "USERS"(_id) ON DELETE CASCADE,
    "track-id" INTEGER,  -- Optional: references tracks(_id) when available
    track_title TEXT,    -- Store title directly for title-based history
    "listened-at" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "listen-duration" INTEGER DEFAULT 0,  -- seconds listened
    completed INTEGER DEFAULT 0           -- 1 if they listened to the whole track
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_listening_history_user_id ON listening_history("user-id");
CREATE INDEX IF NOT EXISTS idx_listening_history_track_id ON listening_history("track-id");
CREATE INDEX IF NOT EXISTS idx_listening_history_listened_at ON listening_history("listened-at");

-- Track requests table
CREATE TABLE IF NOT EXISTS track_requests (
    _id SERIAL PRIMARY KEY,
    "user-id" INTEGER NOT NULL REFERENCES "USERS"(_id) ON DELETE CASCADE,
    track_title TEXT NOT NULL,           -- Track title (Artist - Title format)
    track_path TEXT,                      -- Optional: path to file if known
    message TEXT,                         -- Optional message from requester
    status TEXT DEFAULT 'pending',        -- pending, approved, rejected, played
    "created-at" TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    "reviewed-at" TIMESTAMP,              -- When admin reviewed
    "reviewed-by" INTEGER REFERENCES "USERS"(_id),
    "played-at" TIMESTAMP                 -- When it was actually played
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_track_requests_user_id ON track_requests("user-id");
CREATE INDEX IF NOT EXISTS idx_track_requests_status ON track_requests(status);
CREATE INDEX IF NOT EXISTS idx_track_requests_created ON track_requests("created-at");

-- Adds table for user-created playlists with submission/review workflow
CREATE TABLE IF NOT EXISTS user_playlists (
    _id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES "USERS"(_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    description TEXT,
    track_ids TEXT DEFAULT '[]',  -- JSON array of track IDs
    status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'submitted', 'approved', 'rejected', 'scheduled')),
    created_date INTEGER DEFAULT EXTRACT(EPOCH FROM NOW())::INTEGER,
    submitted_date INTEGER,
    reviewed_date INTEGER,
    reviewed_by INTEGER REFERENCES "USERS"(_id),
    review_notes TEXT
);

-- Create indexes for efficient queries
CREATE INDEX IF NOT EXISTS idx_user_playlists_user_id ON user_playlists(user_id);
CREATE INDEX IF NOT EXISTS idx_user_playlists_status ON user_playlists(status);

-- Create default admin user (password: admin - CHANGE THIS!)
-- Password hash for 'admin' using bcrypt
INSERT INTO "USERS" (username, email, "password-hash", role, active)
-- VALUES ('admin', 'admin@asteroid.radio', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYqYqYqYqYq', 'admin', 1)
VALUES ('admin', 'admin@asteroid.radio','8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918', 'admin', 1)
ON CONFLICT (username) DO NOTHING;

-- Create a test listener user
INSERT INTO "USERS" (username, email, "password-hash", role, active)
VALUES ('listener', 'listener@asteroid.radio', '$2a$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYqYqYqYqYq', 'listener', 1);

-- Grant necessary permissions
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO asteroid;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO asteroid;

-- Create function to update modified_date automatically
CREATE OR REPLACE FUNCTION update_modified_date()
RETURNS TRIGGER AS $$
BEGIN
    NEW.modified_date = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Data retention: function to clean old session data (GDPR compliance)
CREATE OR REPLACE FUNCTION cleanup_old_listener_data(retention_days INTEGER DEFAULT 30)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    -- Delete individual sessions older than retention period
    DELETE FROM listener_sessions 
    WHERE session_start < NOW() - (retention_days || ' days')::INTERVAL;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    
    RAISE NOTICE 'Cleaned up % listener session records older than % days', deleted_count, retention_days;
    
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Create trigger for playlists table
CREATE TRIGGER update_playlists_modified_date
    BEFORE UPDATE ON playlists
    FOR EACH ROW
    EXECUTE FUNCTION update_modified_date();

-- Success message
DO $$
BEGIN
    RAISE NOTICE 'Asteroid Radio database initialized successfully!';
    RAISE NOTICE 'Database: asteroid';
    RAISE NOTICE 'User: asteroid';
    RAISE NOTICE 'Default admin user created: admin / admin (CHANGE PASSWORD!)';
END $$;
