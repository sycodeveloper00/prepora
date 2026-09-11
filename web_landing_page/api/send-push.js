import admin from "firebase-admin";

let app;
try {
  const serviceAccount = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT || "{}");
  if (serviceAccount.projectId && !admin.apps.length) {
    app = admin.initializeApp({
      credential: admin.credential.cert(serviceAccount),
    });
  }
} catch (_) {}

export default async function handler(req, res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "POST") return res.status(405).json({ error: "method_not_allowed" });

  const { targetUid, title, body, type } = req.body || {};
  if (!targetUid || !title || !body) {
    return res.status(400).json({ error: "missing_fields" });
  }

  if (!app) {
    return res.status(500).json({ error: "firebase_not_initialized" });
  }

  const supabaseUrl = process.env.SUPABASE_URL;
  const supabaseKey = process.env.SUPABASE_SERVICE_KEY;
  if (!supabaseUrl || !supabaseKey) {
    return res.status(500).json({ error: "supabase_not_configured" });
  }

  try {
    const userRes = await fetch(
      `${supabaseUrl}/rest/v1/users?id=eq.${targetUid}&select=data&limit=1`,
      {
        headers: {
          apikey: supabaseKey,
          Authorization: `Bearer ${supabaseKey}`,
        },
      }
    );
    const users = await userRes.json();
    const fcmToken = users?.[0]?.data?.fcmToken || users?.[0]?.data?.fcm_token;
    if (!fcmToken) {
      return res.status(200).json({ sent: false, reason: "no_fcm_token" });
    }
    const channelId =
      type === "streak" || type === "streak_warning" || type === "streak_reset"
        ? "streak_channel"
        : "student_notifications";

    await admin.messaging().send({
      token: fcmToken,
      notification: { title, body },
      data: { type: type || "general" },
      android: {
        priority: "high",
        notification: {
          channelId,
          priority: "high",
        },
      },
    });

    return res.status(200).json({ sent: true });
  } catch (e) {
    return res.status(200).json({ sent: false, error: e.message || "send_failed" });
  }
}
