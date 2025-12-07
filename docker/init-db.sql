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
    -- "created-date" integer DEFAULT CURRENT_TIMESTAMP,
    "created-date" integer,
    "last-login" integer,
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
