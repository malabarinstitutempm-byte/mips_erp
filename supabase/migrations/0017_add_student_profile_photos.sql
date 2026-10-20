-- Migration: 0017_add_student_profile_photos.sql
-- Description: Add profile_photo_path, profile_photo_thumb_path, and profile_photo_updated_at columns to students table

ALTER TABLE students 
    ADD COLUMN IF NOT EXISTS profile_photo_path text,
    ADD COLUMN IF NOT EXISTS profile_photo_thumb_path text,
    ADD COLUMN IF NOT EXISTS profile_photo_updated_at timestamptz;
