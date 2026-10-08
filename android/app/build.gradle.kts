import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Task 74: the real upload key. android/key.properties (gitignored, never
// committed) points at a keystore that lives OUTSIDE the repo — see the
// android/SIGNING.md for where it is and why it must be backed up.
// Losing it means this app identity can never ship another update.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) FileInputStream(keystorePropertiesFile).use { load(it) }
}
val hasReleaseSigning = keystorePropertiesFile.exists()

android {
    namespace = "com.runit.run_it"
    // flutter_secure_storage's AAR metadata requires compileSdk 37+, one
    // ahead of Flutter 3.47.0's own default (36) — see Task 24 for the
    // build failure this fixes. compileSdk is compile-time only (which
    // APIs are visible to javac/kotlinc); it doesn't change targetSdk or
    // any runtime behavior, so this is safe independent of minSdk/targetSdk.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The store identity. `namespace` above is only the Kotlin/R package and
        // deliberately stays com.runit.run_it — changing it moves MainActivity
        // for no user-visible gain.
        applicationId = "com.bridgitcampus.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
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
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Never the debug key: without key.properties there's simply no
            // release signing config, and the check below stops the build.
            if (hasReleaseSigning) signingConfig = signingConfigs.getByName("release")
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

// Task 74: fail a release build loudly rather than ever producing one signed
// with the debug key (or unsigned). Debug builds don't need key.properties.
tasks.configureEach {
    if (!hasReleaseSigning && (name == "packageRelease" || name == "signReleaseBundle")) {
        doFirst {
            throw GradleException(
                "Release signing isn't configured: android/key.properties is missing. " +
                    "Restore it (and the upload keystore it points to) from the backup — see android/SIGNING.md.",
            )
        }
    }
}
