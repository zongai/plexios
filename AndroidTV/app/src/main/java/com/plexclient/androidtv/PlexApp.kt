package com.plexclient.androidtv

import android.app.Application
import com.plexclient.androidtv.di.AppContainer

class PlexApp : Application() {
    lateinit var container: AppContainer
        private set

    override fun onCreate() {
        super.onCreate()
        container = AppContainer(this)
    }
}
