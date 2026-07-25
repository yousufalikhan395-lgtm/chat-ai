plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

fun loadSigningProps(): Map<String, String> {
    val f = rootProject.file("key.properties")
    if (!f.exists()) return emptyMap()
    val lines = f.readLines().filter { it.contains("=") && !it.startsWith("#") }
    return lines.associate {
        val parts = it.split("=", limit = 2)
        parts[0].trim() to parts[1].trim()
    }
}

android {
    namespace = "com.chat.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.chat.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    val signingProps = loadSigningProps()
    signingConfigs {
        if (signingProps.isNotEmpty()) {
            create("release") {
                keyAlias = signingProps["keyAlias"]
                keyPassword = signingProps["keyPassword"]
                storeFile = file(signingProps["storeFile"] ?: "")
                storePassword = signingProps["storePassword"]
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                file("proguard-rules.pro")
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
