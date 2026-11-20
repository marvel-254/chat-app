plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials. Kept out of version control (gitignored).
// Generate once with:
//   keytool -genkeypair -v -keystore release.keystore -alias bro-release -keyalg RSA -keysize 2048 -validity 10000
// then write the values to key.properties next to this file.
val keystorePropertiesFile = rootProject.file("app/key.properties")
val keystoreProperties: Map<String, String> = if (keystorePropertiesFile.exists()) {
    // Read key.properties as simple key=value pairs without java.util.Properties
    // (the Kotlin DSL script classpath under AGP 9.x does not expose java.util).
    keystorePropertiesFile.readLines()
        .mapNotNull { line ->
            val trimmed = line.trim()
            if (trimmed.isEmpty() || trimmed.startsWith("#")) null
            else trimmed.split("=", limit = 2).takeIf { it.size == 2 }?.let { it[0].trim() to it[1].trim() }
        }
        .toMap()
} else {
    emptyMap()
}

android {
    namespace = "com.omixsystems.pulsechat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.omixsystems.pulsechat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val store = keystoreProperties["storeFile"]
            val storePasswordValue = keystoreProperties["storePassword"]
            val alias = keystoreProperties["keyAlias"]
            val keyPasswordValue = keystoreProperties["keyPassword"]
            if (!store.isNullOrBlank() &&
                !storePasswordValue.isNullOrBlank() &&
                !alias.isNullOrBlank() &&
                !keyPasswordValue.isNullOrBlank()
            ) {
                storeFile = file(store)
                storePassword = storePasswordValue
                keyAlias = alias
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            val releaseSigning = signingConfigs.getByName("release")
            val releaseStore = releaseSigning.storeFile
            val releaseReady = releaseStore != null && releaseStore.exists()
            signingConfig = if (releaseReady) {
                releaseSigning
            } else {
                // Fallback so `flutter build apk --release` still works before
                // key.properties is present (e.g. first-time local builds).
                signingConfigs.getByName("debug")
            }
            // CI must never publish a debug-signed "release" APK: users could
            // not upgrade it later because the signing identity would change.
            if (System.getenv("REQUIRE_RELEASE_SIGNING") == "true" && !releaseReady) {
                throw org.gradle.api.GradleException(
                    "Release signing is required but key.properties/release.keystore is missing or incomplete."
                )
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
