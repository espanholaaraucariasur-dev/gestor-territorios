# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Play Core — clases opcionales, ignorar si no están presentes
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Biometría — local_auth
-keep class androidx.biometric.** { *; }
-keep class android.hardware.biometrics.** { *; }
-dontwarn androidx.biometric.**

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# Keep R class
-keepclassmembers class **.R$* { public static <fields>; }
