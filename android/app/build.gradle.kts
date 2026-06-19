import java.util.Properties
import java.io.FileInputStream

// 1. Cargar las propiedades del archivo key.properties
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services") // ✅ Firebase
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.congregacion.araucaria_sur"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        create("release") {
            // Se leen dinámicamente desde key.properties, cayendo en tus valores por defecto si no existe el archivo.
            keyAlias = keystoreProperties["keyAlias"] as? String ?: "araucaria_sur"
            keyPassword = keystoreProperties["keyPassword"] as? String ?: "Araucaria2024"
            storeFile = file(keystoreProperties["storeFile"] as? String ?: "araucaria_sur.jks")
            storePassword = keystoreProperties["storePassword"] as? String ?: "Araucaria2024"
        }
    }

    defaultConfig {
        applicationId = "com.congregacion.araucaria_sur"
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            
            // ✅ Recomendado activar minificación para el paquete de producción en la tienda
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}