package com.mendoi.kotodama.ui

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Forum
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.AutoStories
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.stringResource
import com.mendoi.kotodama.R
import com.mendoi.kotodama.feature.home.HomeScreen
import com.mendoi.kotodama.feature.library.LibraryScreen
import com.mendoi.kotodama.feature.timeline.TimelineScreen
import com.mendoi.kotodama.feature.settings.SettingsScreen

private data class TabItem(val labelRes: Int, val icon: ImageVector)

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MainScreen() {
    var selected by remember { mutableIntStateOf(0) }
    val tabs = listOf(
        TabItem(R.string.tab_home, Icons.Filled.Home),
        TabItem(R.string.tab_library, Icons.Filled.AutoStories),
        TabItem(R.string.tab_timeline, Icons.Filled.Forum),
        TabItem(R.string.tab_settings, Icons.Filled.Settings),
    )
    Scaffold(
        bottomBar = {
            NavigationBar {
                tabs.forEachIndexed { i, t ->
                    NavigationBarItem(
                        selected = selected == i,
                        onClick = { selected = i },
                        icon = { Icon(t.icon, contentDescription = stringResource(t.labelRes)) },
                        label = { Text(stringResource(t.labelRes)) }
                    )
                }
            }
        }
    ) { padding ->
        Box(modifier = Modifier.padding(padding)) {
            when (selected) {
                0 -> HomeScreen()
                1 -> LibraryScreen()
                2 -> TimelineScreen()
                3 -> SettingsScreen()
            }
        }
    }
}

@Composable
private fun Box(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    androidx.compose.foundation.layout.Box(modifier = modifier) { content() }
}
