# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase - keep only entry points
-keep class com.google.firebase.FirebaseApp { *; }
-keep class com.google.firebase.auth.** { *; }
-keep class com.google.firebase.firestore.** { *; }
-keep class com.google.firebase.storage.** { *; }
-keep class com.google.firebase.messaging.** { *; }
-keep class com.google.firebase.analytics.** { *; }
-keepattributes Signature
-keepattributes *Annotation*

# Google Play Services
-keep class com.google.android.gms.common.** { *; }
-dontwarn com.google.android.gms.**

# Syncfusion PDF - keep only required classes
-keep class com.syncfusion.pdfviewer.** { *; }
-keep class com.syncfusion.pdfviewer.control.** { *; }
-dontwarn com.syncfusion.**

# Google ML Kit
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.vision.** { *; }
-dontwarn com.google.mlkit.**

# Google Play Core
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# OkHttp / Okio
-dontwarn okhttp3.**
-dontwarn okio.**

# Keep Flutter DeferredComponent classes
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
