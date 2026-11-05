import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

// Push notifications through Firebase: with the project's google-services.json here, the build is
// tied to it; without, the app has no notifications and builds the same.
if (file("google-services.json").exists()) apply(plugin = "com.google.gms.google-services")

// The version follows the iPhone app's (project.yml): app and firmware share one number.
val appVersion: String = Regex("MARKETING_VERSION: \"([^\"]+)\"")
    .find(rootProject.file("../project.yml").readText())?.groupValues?.get(1) ?: "0.0.0"
val appBuild: Int = Regex("CURRENT_PROJECT_VERSION: \"([^\"]+)\"")
    .find(rootProject.file("../project.yml").readText())?.groupValues?.get(1)?.toInt() ?: 1

// The release key comes from the environment (GitHub Actions secrets); without it the APK is
// signed with the debug key, fine for trying it on your own phone.
val keystore = System.getenv("TRACKLAP_KEYSTORE")?.let { file(it) }?.takeIf { it.exists() }

android {
    namespace = "win.tbsgaming.tracklap"
    compileSdk = 35

    defaultConfig {
        // The same as the iPhone app on the App Store; the Kotlin code stays in win.tbsgaming.tracklap.
        applicationId = "win.shadowbyte.tracklap"
        minSdk = 26
        targetSdk = 35
        versionCode = appBuild
        versionName = appVersion
    }

    signingConfigs {
        if (keystore != null) {
            create("release") {
                storeFile = keystore
                storeType = "pkcs12"
                storePassword = System.getenv("TRACKLAP_KEYSTORE_PASSWORD")
                keyAlias = "tracklap"
                keyPassword = System.getenv("TRACKLAP_KEYSTORE_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = if (keystore != null) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources.excludes += "/META-INF/{AL2.0,LGPL2.1}"
    }
}

dependencies {
    val compose = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(compose)
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.15.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-messaging")
    // Firebase brings an old Fragment; the permission requests (registerForActivityResult) want 1.3 or later.
    implementation("androidx.fragment:fragment-ktx:1.8.5")
    implementation("org.osmdroid:osmdroid-android:6.1.20")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.google.zxing:core:3.5.3")
}
