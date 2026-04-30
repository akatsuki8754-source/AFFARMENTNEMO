package com.mendoi.kotodama.feature.home

import android.speech.tts.TextToSpeech
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.mendoi.kotodama.data.DefaultAffirmations
import java.util.Locale

@Composable
fun HomeScreen() {
    val context = LocalContext.current
    val today = remember { DefaultAffirmations.seed.filter { it.morningEnabled }.take(3) }
    val tts = remember {
        var ttsEngine: TextToSpeech? = null
        ttsEngine = TextToSpeech(context) { status ->
            if (status == TextToSpeech.SUCCESS) {
                ttsEngine?.language = Locale.JAPANESE
                ttsEngine?.setSpeechRate(0.9f)
            }
        }
        ttsEngine
    }
    DisposableEffect(Unit) {
        onDispose { tts?.shutdown() }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(16.dp)
            .verticalScroll(rememberScrollState())
    ) {
        Text("こんにちは", style = MaterialTheme.typography.headlineMedium, fontWeight = FontWeight.Bold)
        Spacer(Modifier.height(16.dp))
        Card(
            shape = RoundedCornerShape(16.dp),
            modifier = Modifier.fillMaxWidth()
        ) {
            Column(modifier = Modifier.padding(16.dp)) {
                Text("今日の言葉 (${today.size})",
                    style = MaterialTheme.typography.titleMedium,
                    fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(12.dp))
                today.forEachIndexed { i, aff ->
                    Row(verticalAlignment = Alignment.Top) {
                        Text("${i + 1}. ", style = MaterialTheme.typography.bodyMedium)
                        Text(aff.text, style = MaterialTheme.typography.bodyMedium)
                    }
                    Spacer(Modifier.height(8.dp))
                }
            }
        }
        Spacer(Modifier.height(16.dp))
        Button(
            onClick = {
                today.forEach { aff ->
                    tts?.speak(aff.text, TextToSpeech.QUEUE_ADD, null, aff.id)
                }
            },
            modifier = Modifier.fillMaxWidth().height(64.dp)
        ) {
            Icon(Icons.Filled.PlayArrow, contentDescription = "再生")
            Spacer(Modifier.width(8.dp))
            Text("音読する", style = MaterialTheme.typography.titleMedium)
        }
    }
}
