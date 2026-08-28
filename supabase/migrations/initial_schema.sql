CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  auth_id UUID UNIQUE,
  email TEXT UNIQUE,
  display_name TEXT,
  role TEXT DEFAULT 'student',
  blocked BOOLEAN DEFAULT false,
  block_reason TEXT,
  verified BOOLEAN DEFAULT false,
  photo_url TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS folders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  icon TEXT,
  color TEXT,
  item_count INTEGER DEFAULT 0,
  locked BOOLEAN DEFAULT false,
  updating BOOLEAN DEFAULT false,
  invisible BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS folder_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  folder_id UUID REFERENCES folders(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  content TEXT,
  file_url TEXT,
  file_type TEXT DEFAULT 'text',
  added_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS notices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  file_url TEXT,
  file_type TEXT DEFAULT 'text',
  added_by TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS login_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  device TEXT,
  ip TEXT,
  event TEXT DEFAULT 'login',
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID,
  title TEXT,
  body TEXT,
  read BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS app_updates (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  version TEXT NOT NULL,
  link TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE TABLE IF NOT EXISTS settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT UNIQUE NOT NULL,
  value JSONB
);

-- Supabase Ping Log table (tracks keep-alive pings for all projects)
CREATE TABLE IF NOT EXISTS supabase_ping_log (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_url TEXT NOT NULL,
  project_type TEXT NOT NULL, -- 'system', 'admin_storage', 'assistant_storage'
  account_id TEXT, -- For admin/assistant accounts: the Firestore doc ID
  status TEXT NOT NULL, -- 'success', 'failed', 'paused_530'
  response_time_ms INTEGER,
  error_message TEXT,
  pinged_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_supabase_ping_log_project_url ON supabase_ping_log(project_url);
CREATE INDEX IF NOT EXISTS idx_supabase_ping_log_account_id ON supabase_ping_log(account_id);
CREATE INDEX IF NOT EXISTS idx_supabase_ping_log_pinged_at ON supabase_ping_log(pinged_at DESC);

-- Enable RLS
ALTER TABLE supabase_ping_log ENABLE ROW LEVEL SECURITY;

-- Policy: Service role can insert/read
CREATE POLICY "ping_log_service_all" ON supabase_ping_log FOR ALL USING (auth.role() = 'service_role');
