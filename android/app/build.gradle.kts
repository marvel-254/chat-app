plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ===========================================================================
// Release signing
//
// Credentials live in android/app/key.properties (gitignored):
//
//   storeFile=release.keystore
//   storePassword=...
//   keyAlias=...
//   keyPassword=...
//
// CI writes that file from repository secrets (.github/workflows/build-apk.yml);
// a local machine creates it once with scripts/generate_keystore.sh.
//
// Android only accepts an update when the new APK is signed with the same
// certificate as the installed app. A release APK signed with the debug key
// therefore cannot be installed over a real release, and a rebuilt release
// signed with a *new* key cannot be installed over the previous release either.
// That failure mode is silent at build time, so this script refuses to guess:
//
//   * if key.properties exists but is incomplete or points at a missing/empty
//     keystore, the build fails with an explanation instead of falling back;
//   * if REQUIRE_RELEASE_SIGNING=true (set by CI), a build without a usable
//     release keystore fails instead of producing a debug-signed "release";
//   * a plain local `flutter build apk --release` still works before the
//     keystore exists (debug signing), so first-time setup is not blocked.
// ===========================================================================

val keystorePropertiesFile = rootProject.file("app/key.properties")
val keystoreProperties = mutableMapOf<String, String>()
val keystoreProblems = mutableListOf<String>()
val requiredKeystoreKeys =
    listOf("storeFile", "storePassword", "keyAlias", "keyPassword")

if (keystorePropertiesFile.exists()) {
    for (rawLine in keystorePropertiesFile.readLines()) {
        val line = rawLine.trim()
        if (line.isEmpty() || line.startsWith("#")) continue
        val separator = line.indexOf('=')
        if (separator <= 0) {
            keystoreProblems.add("line is not key=value: \"${line.take(32)}\"")
            continue
        }
        val key = line.substring(0, separator).trim()
        // Users often write storePassword="secret"; keep the quotes out of the
        // credential or the keystore opens with the wrong password.
        val value = line.substring(separator + 1).trim()
            .removeSurrounding("\"")
            .removeSurrounding("'")
        if (key.isNotEmpty()) keystoreProperties[key] = value
    }

    for (key in requiredKeystoreKeys) {
        if (keystoreProperties[key].isNullOrEmpty()) {
            keystoreProblems.add("missing $key")
        }
    }

    val storeFile = keystoreProperties["storeFile"]
    if (!storeFile.isNullOrEmpty()) {
        val resolvedKeystore = file(storeFile)
        when {
            !resolvedKeystore.exists() ->
                keystoreProblems.add("keystore file not found: ${resolvedKeystore.path}")
            resolvedKeystore.length() == 0L ->
                keystoreProblems.add("keystore file is empty: ${resolvedKeystore.path}")
        }
    }
}

val requireReleaseSigning =
    System.getenv("REQUIRE_RELEASE_SIGNING").orEmpty()
        .trim()
        .lowercase() in setOf("1", "true", "yes")
val hasReleaseSigning = keystorePropertiesFile.exists() && keystoreProblems.isEmpty()

if (keystoreProblems.isNotEmpty()) {
    // A half-written key.properties is always a mistake: never sign with the
    // debug key while the caller believes release signing is configured.
    throw GradleException(
        "Release signing is misconfigured in ${keystorePropertiesFile.path}:\n" +
            keystoreProblems.joinToString("\n") { "  - $it" } +
            "\nFix the file, or delete it to build a debug-signed APK locally."
    )
}

if (requireReleaseSigning && !hasReleaseSigning) {
    throw GradleException(
        "REQUIRE_RELEASE_SIGNING=true but ${keystorePropertiesFile.path} is missing. " +
            "CI must write the release keystore from repository secrets " +
            "(KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD). " +
            "Refusing to ship a debug-signed release APK."
    )
}

logger.lifecycle(
    if (hasReleaseSigning) {
        "Release signing: enabled (${keystoreProperties["keyAlias"]} from ${keystoreProperties["storeFile"]})"
    } else {
        "Release signing: not configured - release builds will use the debug key"
    }
)

android {
    namespace = "com.omixsystems.pulsechat"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.omixsystems.pulsechat"
        // You can update the following values to match your application needs.
        // For more information, see: https://docs.flutter.dev/deployment/android#reviewing-the-gradle-build-configuration.
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
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"]
                keyAlias = keystoreProperties["keyAlias"]
                keyPassword = keystoreProperties["keyPassword"]
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                // Local convenience only. CI builds with REQUIRE_RELEASE_SIGNING=true
                // and therefore can never reach this branch.
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
