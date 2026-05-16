# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Play Core
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Biometría — local_auth
-keep class androidx.biometric.** { *; }
-keep class android.hardware.biometrics.** { *; }
-keep class androidx.fragment.app.** { *; }
-keep class androidx.core.hardware.fingerprint.** { *; }
-dontwarn androidx.biometric.**

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.it_nomads.fluttersecurestorage.**

# AndroidX Security — EncryptedSharedPreferences
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# Keep R class
-keepclassmembers class **.R$* { public static <fields>; }
