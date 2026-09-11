"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.onNotificationCreated = exports.onFcmNotification = exports.deleteUser = void 0;
const functions = __importStar(require("firebase-functions"));
const admin = __importStar(require("firebase-admin"));
admin.initializeApp();
exports.deleteUser = functions.https.onCall(async (data, context) => {
    if (!context.auth) {
        throw new functions.https.HttpsError("unauthenticated", "Admin only");
    }
    const callerUid = context.auth.uid;
    const callerDoc = await admin.firestore().collection("users").doc(callerUid).get();
    const callerRole = callerDoc.data()?.role;
    if (callerRole !== "admin") {
        throw new functions.https.HttpsError("permission-denied", "Admin only");
    }
    const uid = data.uid;
    if (!uid) {
        throw new functions.https.HttpsError("invalid-argument", "uid required");
    }
    await admin.auth().deleteUser(uid);
    return { success: true };
});
exports.onFcmNotification = functions.firestore
    .document("fcm_notifications/{docId}")
    .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data || data.sent)
        return;
    const targetUid = data.targetUid;
    const title = data.title;
    const body = data.body;
    const type = data.type || "general";
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
    }
    catch (e) {
        await snap.ref.update({ sent: true, error: e.message || "send_failed" });
    }
});
exports.onNotificationCreated = functions.firestore
    .document("notifications/{docId}")
    .onCreate(async (snap, context) => {
    const data = snap.data();
    if (!data)
        return;
    const uid = data.uid;
    const message = data.message;
    if (!uid || !message)
        return;
    try {
        const userDoc = await admin.firestore().collection("users").doc(uid).get();
        const fcmToken = userDoc.data()?.fcmToken;
        if (!fcmToken)
            return;
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
    }
    catch (e) {
        // silent fail — app-side Firestore listener will handle in-app display
    }
});
//# sourceMappingURL=index.js.map