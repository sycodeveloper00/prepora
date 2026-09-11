import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

export const deleteUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError("unauthenticated", "Admin only");
  }
  const callerUid = context.auth.uid;
  const callerDoc = await admin.firestore().collection("users").doc(callerUid).get();
  const callerRole = callerDoc.data()?.role;
  if (callerRole !== "admin") {
    throw new functions.https.HttpsError("permission-denied", "Admin only");
  }

  const uid = data.uid as string;
  if (!uid) {
    throw new functions.https.HttpsError("invalid-argument", "uid required");
  }

  await admin.auth().deleteUser(uid);
  return { success: true };
});

export const onFcmNotification = functions.firestore
  .document("fcm_notifications/{docId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data || data.sent) return;
    const targetUid = data.targetUid as string;
    const title = data.title as string;
    const body = data.body as string;
    const type = data.type as string || "general";

    try {
      const userDoc = await admin.firestore().collection("users").doc(targetUid).get();
      const fcmToken = userDoc.data()?.fcmToken;
      if (!fcmToken) {
        await snap.ref.update({ sent: true, error: "no_fcm_token" });
        return;
      }

      await admin.messaging().send({
        token: fcmToken,
        notification: { title, body },
        data: { type },
        android: {
          priority: "high",
          notification: {
            channelId: type === "streak" || type === "streak_warning" || type === "streak_reset"
              ? "streak_channel"
              : "student_channel",
            priority: "high",
          },
        },
      });

      await snap.ref.update({ sent: true, sentAt: admin.firestore.FieldValue.serverTimestamp() });
    } catch (e: any) {
      await snap.ref.update({ sent: true, error: e.message || "send_failed" });
    }
  });

export const onNotificationCreated = functions.firestore
  .document("notifications/{docId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data) return;
    const uid = data.uid as string;
    const message = data.message as string;
    if (!uid || !message) return;

    try {
      const userDoc = await admin.firestore().collection("users").doc(uid).get();
      const fcmToken = userDoc.data()?.fcmToken;
      if (!fcmToken) return;

      await admin.messaging().send({
        token: fcmToken,
        notification: { title: "PrePora", body: message },
        data: { type: "notification" },
        android: {
          priority: "high",
          notification: {
            channelId: "student_channel",
            priority: "high",
          },
        },
      });
    } catch (e) {
      // silent fail — app-side Firestore listener will handle in-app display
    }
  });
