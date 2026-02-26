import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cc.lycstar.flutter_ruffle"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cc.lycstar.flutter_ruffle"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    val hasKeystorePropertiesFile = keystorePropertiesFile.exists()
    if (hasKeystorePropertiesFile) {
        keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    }

    val storeFilePath = keystoreProperties["storeFile"]?.toString()?.trim()
    val storePasswordValue = keystoreProperties["storePassword"]?.toString()?.trim()
    val keyAliasValue = keystoreProperties["keyAlias"]?.toString()?.trim()
    val keyPasswordValue = keystoreProperties["keyPassword"]?.toString()?.trim()

    val hasReleaseSigning =
        hasKeystorePropertiesFile &&
            !storeFilePath.isNullOrEmpty() &&
            !storePasswordValue.isNullOrEmpty() &&
            !keyAliasValue.isNullOrEmpty() &&
            !keyPasswordValue.isNullOrEmpty() &&
            file(storeFilePath).exists()

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(storeFilePath!!)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseSigning) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

flutter {
    source = "../.."
}
