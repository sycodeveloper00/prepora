-- ============================================================================
-- 002: Migrate Firestore collections to Supabase (New Account)
-- Run this in the NEW Supabase SQL Editor
-- ============================================================================

-- ──────────────────────────────────────────────────────────────────────────────
-- 1. SETTINGS (replaces Firestore settings/general, notification_config, proxy_config)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT UNIQUE NOT NULL,
  value JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_settings_key ON settings(key);

ALTER TABLE settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "settings_service_all" ON settings FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "settings_anon_read" ON settings FOR SELECT USING (true);

-- Seed proxy_config (value will be updated by app)
INSERT INTO settings (key, value) VALUES ('proxy_config', '{"secret":""}'::jsonb)
ON CONFLICT (key) DO NOTHING;


-- ──────────────────────────────────────────────────────────────────────────────
-- 2. SUPABASE_ACCOUNTS (replaces Firestore supabase_accounts)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS supabase_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_url TEXT NOT NULL,
  service_role_key TEXT NOT NULL,
  anon_key TEXT NOT NULL,
  bucket_status TEXT DEFAULT 'pending',
  failed_buckets TEXT[] DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  storage_limit_mb INTEGER DEFAULT 1024,
  auto_switch_enabled BOOLEAN DEFAULT true,
  current_usage_mb NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_supabase_accounts_active ON supabase_accounts(is_active);

ALTER TABLE supabase_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sa_service_all" ON supabase_accounts FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 3. ASSISTANT_SUPABASE (replaces Firestore assistant_supabase)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS assistant_supabase (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  assistant_uid TEXT NOT NULL,
  assistant_name TEXT,
  project_url TEXT NOT NULL,
  service_role_key TEXT NOT NULL,
  anon_key TEXT NOT NULL,
  bucket_status TEXT DEFAULT 'pending',
  failed_buckets TEXT[] DEFAULT '{}',
  is_active BOOLEAN DEFAULT true,
  storage_limit_mb INTEGER DEFAULT 1024,
  auto_switch_enabled BOOLEAN DEFAULT true,
  current_usage_mb NUMERIC DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_asst_supabase_uid ON assistant_supabase(assistant_uid);
CREATE INDEX IF NOT EXISTS idx_asst_supabase_active ON assistant_supabase(is_active);

ALTER TABLE assistant_supabase ENABLE ROW LEVEL SECURITY;
CREATE POLICY "asst_sa_service_all" ON assistant_supabase FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 4. CLOUDINARY_ACCOUNTS (replaces Firestore cloudinary_accounts)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cloudinary_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cloud_name TEXT NOT NULL,
  upload_preset TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_cloudinary_active ON cloudinary_accounts(is_active);

ALTER TABLE cloudinary_accounts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cloud_service_all" ON cloudinary_accounts FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 5. ASSISTANT_CLOUDINARY (replaces Firestore assistant_cloudinary)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS assistant_cloudinary (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  assistant_uid TEXT NOT NULL,
  assistant_name TEXT,
  cloud_name TEXT NOT NULL,
  upload_preset TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_asst_cloud_uid ON assistant_cloudinary(assistant_uid);
CREATE INDEX IF NOT EXISTS idx_asst_cloud_active ON assistant_cloudinary(is_active);

ALTER TABLE assistant_cloudinary ENABLE ROW LEVEL SECURITY;
CREATE POLICY "asst_cloud_service_all" ON assistant_cloudinary FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 6. AI_API_KEYS (replaces Firestore ai_api_keys)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ai_api_keys (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  provider TEXT NOT NULL,
  base_url TEXT,
  api_key TEXT NOT NULL,
  model TEXT,
  models JSONB,
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_keys_active ON ai_api_keys(is_active);

ALTER TABLE ai_api_keys ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ai_keys_service_all" ON ai_api_keys FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "ai_keys_anon_read" ON ai_api_keys FOR SELECT USING (true);


-- ──────────────────────────────────────────────────────────────────────────────
-- 7. LOGIN_ATTEMPTS (replaces Firestore login_attempts)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS login_attempts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT NOT NULL,
  device_id TEXT,
  device_model TEXT,
  android_version TEXT,
  timestamp TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_login_attempts_uid ON login_attempts(uid);
CREATE INDEX IF NOT EXISTS idx_login_attempts_created ON login_attempts(created_at DESC);

ALTER TABLE login_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "login_att_service_all" ON login_attempts FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 8. LOGIN_HISTORY (replaces Firestore login_history subcollection)
-- Flattened: each row = one login event for one user
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS login_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  device TEXT,
  device_id TEXT,
  android_version TEXT,
  ip TEXT,
  event TEXT DEFAULT 'login',
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_login_history_uid ON login_history(user_id);
CREATE INDEX IF NOT EXISTS idx_login_history_created ON login_history(created_at DESC);

ALTER TABLE login_history ENABLE ROW LEVEL SECURITY;
CREATE POLICY "login_hist_service_all" ON login_history FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 9. ASSISTANT_ACCESS (replaces Firestore Assistant_access)
-- Folder-level access grants for assistant users
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS assistant_access (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT NOT NULL,
  folder_id TEXT NOT NULL,
  name TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_asst_access_uid ON assistant_access(uid);
CREATE INDEX IF NOT EXISTS idx_asst_access_folder ON assistant_access(folder_id);

ALTER TABLE assistant_access ENABLE ROW LEVEL SECURITY;
CREATE POLICY "asst_acc_service_all" ON assistant_access FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 10. CONTENT_ASSISTANT_ACCESS (replaces Firestore content_Assistant_access)
-- Content-level access grants for assistant users
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS content_assistant_access (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  content_id TEXT NOT NULL,
  folder_id TEXT NOT NULL,
  name TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_caa_uid ON content_assistant_access(user_id);
CREATE INDEX IF NOT EXISTS idx_caa_content ON content_assistant_access(content_id);
CREATE INDEX IF NOT EXISTS idx_caa_folder ON content_assistant_access(folder_id);

ALTER TABLE content_assistant_access ENABLE ROW LEVEL SECURITY;
CREATE POLICY "caa_service_all" ON content_assistant_access FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 11. CONVERSATIONS (replaces Firestore users/{uid}/conversations)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT NOT NULL,
  title TEXT,
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_conv_uid ON conversations(uid);
CREATE INDEX IF NOT EXISTS idx_conv_updated ON conversations(updated_at DESC);

ALTER TABLE conversations ENABLE ROW LEVEL SECURITY;
CREATE POLICY "conv_service_all" ON conversations FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 12. MESSAGES (replaces Firestore users/{uid}/conversations/{id}/messages)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL,
  uid TEXT NOT NULL,
  role TEXT NOT NULL,
  content TEXT NOT NULL,
  timestamp TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_msg_conv ON messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_msg_uid ON messages(uid);
CREATE INDEX IF NOT EXISTS idx_msg_ts ON messages(timestamp ASC);

ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
CREATE POLICY "msg_service_all" ON messages FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 13. USERS (replaces Firestore users — extended fields not in auth)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_id TEXT UNIQUE NOT NULL,
  email TEXT,
  display_name TEXT,
  role TEXT DEFAULT 'student',
  blocked BOOLEAN DEFAULT false,
  block_reason TEXT,
  verified BOOLEAN DEFAULT false,
  photo_url TEXT,
  auto_download BOOLEAN DEFAULT false,
  terms_accepted BOOLEAN DEFAULT false,
  terms_accepted_at TIMESTAMPTZ,
  current_device_id TEXT,
  last_login_at TIMESTAMPTZ,
  streak_count INTEGER DEFAULT 0,
  streak_best INTEGER DEFAULT 0,
  total_active_days INTEGER DEFAULT 0,
  last_active_date TEXT,
  free_trial_start TIMESTAMPTZ,
  free_trial_end TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_users_auth_id ON users(auth_id);
CREATE INDEX IF NOT EXISTS idx_users_email ON users(email);
CREATE INDEX IF NOT EXISTS idx_users_role ON users(role);

ALTER TABLE users ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_service_all" ON users FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "users_anon_read" ON users FOR SELECT USING (true);


-- ──────────────────────────────────────────────────────────────────────────────
-- 14. FOLDERS (replaces Firestore folders — group_link fields)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  icon TEXT,
  color TEXT,
  item_count INTEGER DEFAULT 0,
  locked BOOLEAN DEFAULT false,
  updating BOOLEAN DEFAULT false,
  invisible BOOLEAN DEFAULT false,
  group_link TEXT,
  inherit_group BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE folders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "folders_service_all" ON folders FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "folders_anon_read" ON folders FOR SELECT USING (true);


-- ──────────────────────────────────────────────────────────────────────────────
-- 15. CONTENTS (replaces Firestore folders/{id}/contents)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS contents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  folder_id UUID REFERENCES folders(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  content TEXT,
  file_url TEXT,
  file_type TEXT DEFAULT 'text',
  added_by TEXT,
  group_link TEXT,
  inherit_group BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_contents_folder ON contents(folder_id);

ALTER TABLE contents ENABLE ROW LEVEL SECURITY;
CREATE POLICY "contents_service_all" ON contents FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "contents_anon_read" ON contents FOR SELECT USING (true);


-- ──────────────────────────────────────────────────────────────────────────────
-- 16. NOTICES
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  file_url TEXT,
  file_type TEXT DEFAULT 'text',
  added_by TEXT,
  is_pinned BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE notices ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notices_service_all" ON notices FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "notices_anon_read" ON notices FOR SELECT USING (true);


-- ──────────────────────────────────────────────────────────────────────────────
-- 17. NOTIFICATIONS
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  title TEXT,
  body TEXT,
  read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notif_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notif_read ON notifications(read);

ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notif_service_all" ON notifications FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 18. WEB_SESSIONS (replaces Firestore web_sessions)
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS web_sessions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id TEXT UNIQUE NOT NULL,
  user_id TEXT NOT NULL,
  connected BOOLEAN DEFAULT true,
  connected_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ws_user ON web_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_ws_session ON web_sessions(session_id);

ALTER TABLE web_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ws_service_all" ON web_sessions FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 19. APP_UPDATES
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app_updates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  version TEXT NOT NULL,
  link TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE app_updates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "updates_service_all" ON app_updates FOR ALL USING (auth.role() = 'service_role');
CREATE POLICY "updates_anon_read" ON app_updates FOR SELECT USING (true);


-- ──────────────────────────────────────────────────────────────────────────────
-- 20. NOTES
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS notes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  uid TEXT NOT NULL,
  lecture_name TEXT,
  content TEXT,
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notes_uid ON notes(uid);

ALTER TABLE notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "notes_service_all" ON notes FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 21. FEEDBACKS
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS feedbacks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  folder_id TEXT,
  content_id TEXT,
  rating INTEGER,
  comment TEXT,
  status TEXT DEFAULT 'pending',
  reply TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_fb_user ON feedbacks(user_id);
CREATE INDEX IF NOT EXISTS idx_fb_status ON feedbacks(status);

ALTER TABLE feedbacks ENABLE ROW LEVEL SECURITY;
CREATE POLICY "fb_service_all" ON feedbacks FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 22. STUDENT_ACTIVITIES
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS student_activities (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id TEXT NOT NULL,
  folder_id TEXT,
  content_id TEXT,
  started_at TIMESTAMPTZ DEFAULT now(),
  ended_at TIMESTAMPTZ,
  duration_seconds INTEGER DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_sa_user ON student_activities(user_id);

ALTER TABLE student_activities ENABLE ROW LEVEL SECURITY;
CREATE POLICY "sa_act_service_all" ON student_activities FOR ALL USING (auth.role() = 'service_role');


-- ──────────────────────────────────────────────────────────────────────────────
-- 23. SUPABASE_PING_LOG
-- ──────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS supabase_ping_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_url TEXT NOT NULL,
  project_type TEXT NOT NULL,
  account_id TEXT,
  status TEXT NOT NULL,
  response_time_ms INTEGER,
  error_message TEXT,
  pinged_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ping_url ON supabase_ping_log(project_url);
CREATE INDEX IF NOT EXISTS idx_ping_account ON supabase_ping_log(account_id);
CREATE INDEX IF NOT EXISTS idx_ping_at ON supabase_ping_log(pinged_at DESC);

ALTER TABLE supabase_ping_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY "ping_service_all" ON supabase_ping_log FOR ALL USING (auth.role() = 'service_role');


-- ============================================================================
-- DONE — 23 tables ready. All service_role policies for proxy access.
-- ============================================================================
