package win.tbsgaming.tracklap

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import win.tbsgaming.tracklap.model.DragMeasure
import win.tbsgaming.tracklap.model.Units
import win.tbsgaming.tracklap.timing.DragEvent
import win.tbsgaming.tracklap.timing.LapEvent
import win.tbsgaming.tracklap.ui.Fmt
import win.tbsgaming.tracklap.ui.L
import win.tbsgaming.tracklap.ui.Strings
import java.text.NumberFormat
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/**
 * Reads the lap time and the gap out loud at the end of each lap, and the main measures of a drag
 * run, turning the music down meanwhile.
 */
class LapVoice(context: Context) {
    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val attributes = AudioAttributes.Builder()
        .setUsage(AudioAttributes.USAGE_ASSISTANCE_NAVIGATION_GUIDANCE)
        .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
        .build()
    private val focus = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK).setAudioAttributes(attributes).build()
    private var ready = false
    private val locale = Locale(Strings.language)
    private val tts: TextToSpeech = TextToSpeech(context.applicationContext) { status ->
        ready = status == TextToSpeech.SUCCESS
        if (ready) {
            tts.language = locale
            tts.setAudioAttributes(attributes)
        }
    }

    init {
        tts.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
            override fun onStart(utteranceId: String?) {}
            override fun onDone(utteranceId: String?) { audio.abandonAudioFocusRequest(focus) }
            @Deprecated("Deprecated in Java")
            override fun onError(utteranceId: String?) { audio.abandonAudioFocusRequest(focus) }
        })
    }

    private fun numbers(digits: Int) = NumberFormat.getNumberInstance(locale).apply {
        minimumFractionDigits = 1
        maximumFractionDigits = digits
    }

    fun announce(e: LapEvent, place: win.tbsgaming.tracklap.multiplayer.Place? = null) {
        val parts = ArrayList<String>()
        if (e.isRecord) parts.add(L("Nuovo record della pista")) else if (e.isBest) parts.add(L("Nuovo best"))
        // "1 32.4" is read as one, thirty-two point four.
        val minutes = (e.time / 60).toInt()
        val seconds = numbers(1).format(e.time - minutes * 60)
        parts.add(if (minutes > 0) "$minutes $seconds" else seconds)
        e.gap?.let { gap ->
            val value = numbers(if (abs(gap) < 1) 2 else 1).format(abs(gap))
            parts.add(if (gap < 0) L("meno %@", value) else L("più %@", value))
        }
        val rival = e.rival
        val rivalGap = e.rivalGap
        if (rival != null && rivalGap != null) {
            val value = numbers(if (abs(rivalGap) < 1) 2 else 1).format(abs(rivalGap))
            parts.add(if (rivalGap < 0) L("%@: meno %@", rival, value) else L("%@: più %@", rival, value))
        }
        if (place != null) {
            parts.add(
                if (place.position == 1) L("primo nel gruppo")
                else L("posizione %lld, a %@ da %@", place.position, numbers(if (abs(place.gap) < 1) 2 else 1).format(abs(place.gap)), place.rival),
            )
        }
        say(parts.joinToString(", "))
    }

    /** 0–100, the quarter mile and the stop of a drag run, as they are done. */
    fun announce(e: DragEvent) {
        val seconds = numbers(if (e.result.time < 10) 2 else 1).format(e.result.time)
        val m = e.measure
        val parts = ArrayList<String>()
        if (e.isRecord) parts.add(L("Nuovo record"))
        when (m.kind) {
            DragMeasure.Kind.speed -> parts.add(
                L("da %lld a %lld: %@ secondi", (m.from * Fmt.speedFactor).roundToInt(), (m.to * Fmt.speedFactor).roundToInt(), seconds),
            )
            DragMeasure.Kind.distance -> parts.add(L("%@: %@ secondi a %lld", spoken(m), seconds, (e.result.speed * Fmt.speedFactor).roundToInt()))
            DragMeasure.Kind.braking -> {
                val from = (m.from * Fmt.speedFactor).roundToInt()
                if (Units.current == Units.metric) parts.add(L("frenata da %lld: %@ metri", from, numbers(1).format(e.result.distance)))
                else parts.add(L("frenata da %lld: %lld piedi", from, (e.result.distance * 3.28084).roundToInt()))
            }
        }
        say(parts.joinToString(", "))
    }

    private fun spoken(m: DragMeasure) = when (m.name) {
        "1/4 mi" -> L("quarto di miglio")
        "1/8 mi" -> L("ottavo di miglio")
        "1/2 mi" -> L("mezzo miglio")
        else -> m.name
    }

    private fun say(text: String) {
        if (!ready) return
        audio.requestAudioFocus(focus)
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "tracklap")
    }

    fun shutdown() = tts.shutdown()
}
