# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Play Core — clases opcionales, ignorar si no están presentes
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Keep R class
-keepclassmembers class **.R$* { public static <fields>; }
