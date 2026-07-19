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
