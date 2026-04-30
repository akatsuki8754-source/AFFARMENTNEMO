package com.mendoi.kotodama

import android.app.Application
import com.google.firebase.FirebaseApp
import com.google.firebase.appcheck.FirebaseAppCheck
import com.google.firebase.appcheck.debug.DebugAppCheckProviderFactory
import com.google.firebase.appcheck.playintegrity.PlayIntegrityAppCheckProviderFactory
import com.google.android.gms.ads.MobileAds

class KotodamaApp : Application() {
    override fun onCreate() {
        super.onCreate()

        // Firebase + App Check (Phase 3 Gemini で使う)
        FirebaseApp.initializeApp(this)
        val factory = if (BuildConfig.DEBUG) {
            DebugAppCheckProviderFactory.getInstance()
        } else {
            PlayIntegrityAppCheckProviderFactory.getInstance()
        }
        FirebaseAppCheck.getInstance().installAppCheckProviderFactory(factory)

        // AdMob 初期化
        MobileAds.initialize(this) {}
    }
}
