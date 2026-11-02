# Suprimir únicamente la referencia opcional del plugin In-App Update.
# Flutter, Firebase, biometría y secure storage incluyen sus propias consumer
# rules; no mantener paquetes enteros porque bloquea la optimización de R8.
-dontwarn com.google.android.play.core.**
