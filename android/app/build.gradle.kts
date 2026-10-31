import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyFile = rootProject.file("key.properties")
val releaseKeyProperties = Properties().apply {
    if (releaseKeyFile.exists()) {
        releaseKeyFile.inputStream().use { load(it) }
    }
}
if (releaseKeyFile.exists()) {
    val requiredKeys = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    val missingKeys = requiredKeys.filter { releaseKeyProperties.getProperty(it).isNullOrBlank() }
    check(missingKeys.isEmpty()) {
        "Missing ${missingKeys.joinToString()} in android/key.properties."
    }
}

android {
    namespace = "com.klasify.app"
    // Google Play has required API 36 for new apps and updates since
    // August 31, 2026. maxOf keeps us at 36+ even if the installed Flutter
    // SDK's default is older, without ever lowering a newer default.
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    // No ndkVersion declared on purpose: every plugin ships prebuilt .so
    // libraries (paddle_ocr_native bundles ONNX Runtime), so no NDK is
    // needed to compile, and skipping it keeps CI/low-disk builds light.

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Choose a permanent, globally unique ID before publishing; changing it later
        // makes Android treat an update as a different app.
        applicationId = "io.github.carlsibug98_spec.klasify"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // paddle_ocr_native ships its ONNX Runtime only for Android API 26+.
        minSdk = maxOf(flutter.minSdkVersion, 26)
        // Google Play target-API requirement: new apps and app updates must
        // target API 36+ (deadline August 31, 2026, already in force).
        // Staying below only blocks *updates* — but the first public release
        // counts as a new app, so 36 is the floor from day one.
        targetSdk = maxOf(flutter.targetSdkVersion, 36)
        ndk {
            abiFilters += "arm64-v8a"
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = releaseKeyProperties.getProperty("keyAlias")
            keyPassword = releaseKeyProperties.getProperty("keyPassword")
            storePassword = releaseKeyProperties.getProperty("storePassword")
            storeFile = releaseKeyProperties.getProperty("storeFile")?.let { rootProject.file(it) }
        }
    }

    buildTypes {
        release {
            // Leave release artifacts unsigned until the developer supplies their own key.
            if (releaseKeyFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// PaddleOCR's bundled native runtime currently supports arm64-v8a only.
android {
    packaging {
        jniLibs {
            excludes += setOf(
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
            )
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


dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
