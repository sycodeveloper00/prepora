import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter Gradle Plugin must be applied after Android and Kotlin plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Load signing credentials from key.properties (local) or environment variables (CI).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}
val ksStoreFilePath = System.getenv("RELEASE_KEYSTORE_PATH")
    ?: keystoreProperties.getProperty("storeFile")
val ksStorePassword = System.getenv("RELEASE_KEYSTORE_PASSWORD")
    ?: keystoreProperties.getProperty("storePassword")
val ksKeyAlias = System.getenv("RELEASE_KEY_ALIAS")
    ?: keystoreProperties.getProperty("keyAlias")

android {
    namespace = "com.prepora.academy.prepora"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.prepora.academy.prepora"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (ksStoreFilePath != null) {
                val resolvedStoreFile = if (File(ksStoreFilePath).isAbsolute) ksStoreFilePath else "$rootDir/$ksStoreFilePath"
                storeFile = file(resolvedStoreFile)
                storePassword = ksStorePassword
                keyAlias = ksKeyAlias
                keyPassword = ksStorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (ksStoreFilePath != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        jniLibs {
            excludes += listOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**"
            )
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
