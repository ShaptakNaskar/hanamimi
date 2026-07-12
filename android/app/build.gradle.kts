import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing lives in android/key.properties (gitignored).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.hanamimi.app"
    // Pinned above flutter.compileSdkVersion (35): screen_brightness_android
    // 2.x compiles against SDK 36. compileSdk is backward compatible and
    // changes nothing at runtime — targetSdk below still rules behaviour.
    compileSdk = 36
    ndkVersion = "27.0.12077973" // highest required by plugins

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // Plus flavor installs side-by-side with the Play Store build.
        applicationId = "com.hanamimi.app.plus"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // No ndk.abiFilters here: Gradle rejects them alongside the
        // CI's --split-per-abi builds ("Conflicting configuration").
        // The per-ABI release APKs keep downloads small; only the
        // universal APK carries every ABI's yt-dlp Python payload.
    }

    // youtubedl-android loads its bundled Python .so from the extracted
    // native-lib directory, so the libs must NOT stay compressed inside
    // the APK. (Default is false on modern AGP.)
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Fallback so `flutter run --release` works on a fresh clone.
                signingConfigs.getByName("debug")
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // M28 — embedded, self-updating yt-dlp (Python 3 + yt-dlp) for
    // YouTube stream resolution. GPLv3: linking makes this build GPLv3,
    // which is fine for the plus (sideload, unofficial-API) branch and
    // MUST never be merged to the Play-Store `main` branch. No :ffmpeg
    // and no :aria2c — we only need a deciphered bestaudio URL.
    implementation("io.github.junkfood02.youtubedl-android:library:0.18.1")
}
