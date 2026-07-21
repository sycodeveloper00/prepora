# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase - keep only entry points needed for reflection
-keep class com.google.firebase.FirebaseApp { *; }
-keepclassmembers class * {
    @com.google.firebase.auth.FirebaseAuthException <fields>;
}
-keepattributes Signature
-keepattributes *Annotation*

# Google Play Services
-dontwarn com.google.android.gms.**

# Syncfusion PDF - keep only required control classes
-keep class com.syncfusion.pdfviewer.control.SfPdfViewer { *; }
-dontwarn com.syncfusion.**

# Google ML Kit - keep only text recognition entry point
-keep class com.google.mlkit.vision.text.** { *; }
-dontwarn com.google.mlkit.**

# OkHttp / Okio
-dontwarn okhttp3.**
-dontwarn okio.**

# Remove logging in release
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
