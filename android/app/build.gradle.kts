plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.FileInputStream
import java.util.Properties

// Repo-root keystore.properties (gitignored), same pattern as BumpDesk.
val keystorePropertiesFile = rootProject.file("../keystore.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.blushcraft.blushcraft"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.blushcraft.blushcraft"
        minSdk = 26
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Universal APK ABIs supported by current Flutter engine.
        // (32-bit x86 is no longer shipped by Flutter; use x86_64 emulators.)
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a", "x86_64")
        }
    }

    // One fat APK (not split-per-abi).
    splits {
        abi {
            isEnable = false
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = rootProject.file("../${keystoreProperties.getProperty("storeFile")!!}")
                storePassword = keystoreProperties.getProperty("storePassword")
                val placeholders = setOf("CHANGE_ME", "changeme", "")
                check(!placeholders.contains(storePassword) && !placeholders.contains(keyPassword)) {
                    "Update keystore.properties with the passwords from keytool (still using placeholder values)."
                }
            } else {
                val storeFileEnv = System.getenv("RELEASE_STORE_FILE")
                if (storeFileEnv != null) {
                    storeFile = rootProject.file(storeFileEnv)
                    storePassword = System.getenv("RELEASE_STORE_PASSWORD")
                    keyAlias = System.getenv("RELEASE_KEY_ALIAS")
                    keyPassword = System.getenv("RELEASE_KEY_PASSWORD")
                }
            }
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.getByName("release")
            signingConfig = if (releaseSigning.storeFile?.isFile == true) {
                releaseSigning
            } else {
                // Local/dev builds without keystore.properties still produce an installable APK.
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
