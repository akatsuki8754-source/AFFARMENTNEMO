plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
}

android {
    namespace = "com.mendoi.kotodama"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.mendoi.kotodama"
        minSdk = 26
        targetSdk = 35
        versionCode = 2
        versionName = "1.0.3"
        // ユーザー要望: 全ロケール対応
        resourceConfigurations.addAll(listOf("ja", "en", "zh-rCN", "zh-rTW", "ko", "de", "es", "fr", "pt-rBR", "ru"))
        vectorDrawables { useSupportLibrary = true }
    }

    // ★ 順序重要: signingConfigs を buildTypes より先に定義する
    signingConfigs {
        create("release") {
            // ハードコード fallback でもデフォルト値を解決できるように
            val keystorePath = System.getenv("KOTODAMA_KEYSTORE")
                ?: "${System.getProperty("user.home")}/.kotodama-secrets/kotodama-release.jks"
            val storePass = System.getenv("KOTODAMA_KEYSTORE_PASSWORD") ?: "kotodama2026"
            val alias = System.getenv("KOTODAMA_KEY_ALIAS") ?: "kotodama"
            val keyPass = System.getenv("KOTODAMA_KEY_PASSWORD") ?: "kotodama2026"
            if (file(keystorePath).exists()) {
                storeFile = file(keystorePath)
                storePassword = storePass
                keyAlias = alias
                keyPassword = keyPass
                println("[signingConfig] release: using $keystorePath")
            } else {
                println("[signingConfig] release: keystore NOT found at $keystorePath — fallback to debug")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
        debug {
            // applicationIdSuffix removed for google-services.json compat
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures {
        compose = true
        buildConfig = true
    }
    packaging {
        resources { excludes += "/META-INF/{AL2.0,LGPL2.1}" }
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.datastore:datastore-preferences:1.1.1")

    // Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:33.7.0"))
    implementation("com.google.firebase:firebase-analytics-ktx")
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.firebase:firebase-firestore-ktx")
    implementation("com.google.firebase:firebase-functions-ktx")
    implementation("com.google.firebase:firebase-appcheck-ktx")
    implementation("com.google.firebase:firebase-appcheck-debug")
    implementation("com.google.firebase:firebase-appcheck-playintegrity")
    implementation("com.google.firebase:firebase-crashlytics-ktx")
    implementation("com.google.firebase:firebase-perf-ktx")

    // AdMob
    implementation("com.google.android.gms:play-services-ads:23.6.0")
    implementation("com.google.android.ump:user-messaging-platform:3.0.0")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.1")
}
