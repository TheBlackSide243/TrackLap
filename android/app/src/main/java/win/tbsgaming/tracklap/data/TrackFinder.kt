package win.tbsgaming.tracklap.data

import android.util.Xml
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import org.xmlpull.v1.XmlPullParser
import win.tbsgaming.tracklap.BuildConfig
import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.GeoBox
import win.tbsgaming.tracklap.model.Geo
import win.tbsgaming.tracklap.model.Track
import win.tbsgaming.tracklap.ui.Fmt
import win.tbsgaming.tracklap.ui.L
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.util.Locale

data class TrackCandidate(
    val id: String,
    val name: String,
    val kind: Kind,
    val center: Coord,
    val place: String = "",
    /** The venue's area on OpenStreetMap, when known: the raceway ways are looked for inside it. */
    val box: GeoBox? = null,
    /** ISO country code, for the catalog. */
    val country: String = "",
    val distanceKm: Double? = null,
) {
    enum class Kind { circuit, karting, other }

    val kindTitle: String
        get() = when (kind) {
            Kind.circuit -> L("Autodromo")
            Kind.karting -> L("Kartodromo")
            Kind.other -> L("Pista")
        }

    val subtitle: String
        get() {
            val parts = arrayListOf(kindTitle)
            if (place.isNotEmpty()) parts.add(place)
            distanceKm?.let { parts.add(Fmt.distance(it * 1000)) }
            return parts.joinToString(" · ")
        }

    val searchBox: GeoBox
        get() {
            if (box != null && box.area > 1e-6) return box.padded(350.0)
            return GeoBox.around(center, if (kind == Kind.karting) 700.0 else 2500.0)
        }
}

data class PlaceCandidate(val id: String, val name: String, val detail: String, val center: Coord)

class FinderBusy : Exception(L("OpenStreetMap non risponde in questo momento: riprova tra poco."))

object Net {
    val userAgent = "TrackLap/${BuildConfig.VERSION_NAME} (Android lap timer)"

    suspend fun get(url: String, timeoutMs: Int): String = withContext(Dispatchers.IO) {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.connectTimeout = timeoutMs
            c.readTimeout = timeoutMs
            c.setRequestProperty("User-Agent", userAgent)
            if (c.responseCode != 200) throw FinderBusy()
            c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
        } finally {
            c.disconnect()
        }
    }

    suspend fun <T> getStream(url: String, timeoutMs: Int, read: (InputStream) -> T): T = withContext(Dispatchers.IO) {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.connectTimeout = timeoutMs
            c.readTimeout = timeoutMs
            c.setRequestProperty("User-Agent", userAgent)
            if (c.responseCode != 200) throw FinderBusy()
            c.inputStream.use(read)
        } finally {
            c.disconnect()
        }
    }

    suspend fun post(url: String, form: String, timeoutMs: Int): String = withContext(Dispatchers.IO) {
        val c = URL(url).openConnection() as HttpURLConnection
        try {
            c.connectTimeout = timeoutMs
            c.readTimeout = timeoutMs
            c.requestMethod = "POST"
            c.doOutput = true
            c.setRequestProperty("User-Agent", userAgent)
            c.setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            c.outputStream.use { it.write(form.toByteArray(Charsets.UTF_8)) }
            if (c.responseCode != 200) throw FinderBusy()
            c.inputStream.use { it.readBytes().toString(Charsets.UTF_8) }
        } finally {
            c.disconnect()
        }
    }

    fun enc(s: String): String = URLEncoder.encode(s, "UTF-8")
}

/** The first answer of several tries that runs without throwing; null when none does. */
suspend fun <T> firstAnswer(vararg tries: suspend () -> T?): T? = coroutineScope {
    val answers = Channel<T?>(tries.size)
    val jobs = tries.map { t -> launch { answers.send(runCatching { t() }.getOrNull()) } }
    var result: T? = null
    repeat(tries.size) {
        val a = answers.receive()
        if (a != null && result == null) {
            result = a
            jobs.forEach { it.cancel() }
            return@coroutineScope a
        }
    }
    result
}

/** Tells motorsport venues from other sports centres, and whole circuits from their named corners. */
object TrackWords {
    private val motor = listOf("autodrom", "autódrom", "circuit", "raceway", "speedway", "racetrack", "race track",
        "motodrom", "motódrom", "kart", "rennstrecke", "motorsport", "motocross", "rallycross",
        "autocross", "motorpark", "motor park", "racing", "drift", "minimoto", "supermotard",
        "okruh", "sirkuit", "サーキット", "スピードウェイ", "赛车", "賽車", "حلبة")
    private val corners = setOf("curva", "curve", "turn", "virage", "kurve", "corner", "chicane", "variante", "tornante",
        "hairpin", "épingle", "pit", "pitlane", "box", "rettilineo", "straight", "esse", "s")
    private val notRing = setOf("spring", "springs", "string", "boxring", "eisring")

    fun kind(name: String, tag: String, box: GeoBox?): TrackCandidate.Kind? {
        val n = name.lowercase()
        val motorName = isMotor(n)
        when (tag) {
            "highway:raceway" -> {
                if (isCorner(n)) return null
                // A short named raceway is a corner or a pit lane, unless the name says otherwise.
                if (box != null && !motorName && diagonal(box) < 300) return null
            }
            "leisure:sports_centre", "leisure:track", "leisure:stadium" -> if (!motorName) return null
            else -> return null
        }
        if (n.contains("kart")) return TrackCandidate.Kind.karting
        if (n.contains("cross") || n.startsWith("mx ")) return TrackCandidate.Kind.other
        return TrackCandidate.Kind.circuit
    }

    private fun isMotor(n: String): Boolean {
        if (motor.any { n.contains(it) }) return true
        val words = n.split(Regex("[^\\p{L}]+")).filter { it.isNotEmpty() }
        return words.any { it.endsWith("ring") && it !in notRing }
    }

    private fun isCorner(n: String): Boolean {
        val first = n.split(Regex("[^\\p{L}\\p{N}]+")).firstOrNull { it.isNotEmpty() } ?: n
        if (first in corners) return true
        // "T1", "T12": turn numbers.
        return first.length in 2..3 && first.startsWith("t") && first.drop(1).all { it.isDigit() }
    }

    private fun diagonal(b: GeoBox) = Geo.distance(Coord(b.minLat, b.minLon), Coord(b.maxLat, b.maxLon))
}

/** Name search on OpenStreetMap through Photon (komoot): fast, worldwide, forgiving of typos. */
object Photon {
    private const val BASE = "https://photon.komoot.io/api/"
    private val trackTags = listOf("leisure:sports_centre", "leisure:track", "leisure:stadium", "highway:raceway")
    private val placeTags = listOf("place:city", "place:town", "place:village", "place:municipality")

    /** Photon names things in English, German or French on request; otherwise in the local language. */
    private val language: String?
        get() = Locale.getDefault().language.takeIf { it in listOf("en", "de", "fr") }

    private suspend fun features(params: List<Pair<String, String>>): List<JsonObject> {
        val all = params + (language?.let { listOf("lang" to it) } ?: emptyList())
        val url = BASE + "?" + all.joinToString("&") { "${it.first}=${Net.enc(it.second)}" }
        val text = Net.get(url, 12_000)
        return Files.json.parseToJsonElement(text).jsonObject["features"]?.jsonArray?.map { it.jsonObject } ?: emptyList()
    }

    private fun JsonObject.str(k: String) = this[k]?.jsonPrimitive?.contentOrNull

    suspend fun tracks(q: String, box: GeoBox? = null, limit: Int = 25): List<TrackCandidate> {
        val p = arrayListOf("q" to q, "limit" to "$limit")
        p += trackTags.map { "osm_tag" to it }
        if (box != null) p += "bbox" to "${box.minLon},${box.minLat},${box.maxLon},${box.maxLat}"
        return features(p).mapNotNull { candidate(it) }
    }

    suspend fun places(q: String): List<PlaceCandidate> {
        val p = arrayListOf("q" to q, "limit" to "4")
        p += placeTags.map { "osm_tag" to it }
        return features(p).mapNotNull { f ->
            val props = f["properties"]?.jsonObject ?: return@mapNotNull null
            val c = f["geometry"]?.jsonObject?.get("coordinates")?.jsonArray ?: return@mapNotNull null
            val name = props.str("name") ?: return@mapNotNull null
            if (c.size != 2) return@mapNotNull null
            val detail = listOfNotNull(props.str("state") ?: props.str("county"), props.str("country")).joinToString(", ")
            PlaceCandidate("${props.str("osm_type")}${props.str("osm_id")}", name, detail,
                Coord(c[1].jsonPrimitive.doubleOrNull ?: 0.0, c[0].jsonPrimitive.doubleOrNull ?: 0.0))
        }
    }

    /** Venues in a box whose names carry the usual words, as a quick first answer for "near me". */
    suspend fun nearby(box: GeoBox): List<TrackCandidate> = coroutineScope {
        listOf("circuit", "autodromo", "kart", "raceway", "ring")
            .map { w -> async { runCatching { tracks(w, box, 20) }.getOrDefault(emptyList()) } }
            .awaitAll().flatten()
    }

    private fun candidate(f: JsonObject): TrackCandidate? {
        val p = f["properties"]?.jsonObject ?: return null
        val c = f["geometry"]?.jsonObject?.get("coordinates")?.jsonArray ?: return null
        val name = p.str("name")?.takeIf { it.isNotEmpty() } ?: return null
        if (c.size != 2) return null
        var box: GeoBox? = null
        val e = p["extent"] as? JsonArray
        if (e != null && e.size == 4) {
            val v = e.map { it.jsonPrimitive.doubleOrNull ?: 0.0 }
            box = GeoBox(minOf(v[1], v[3]), minOf(v[0], v[2]), maxOf(v[1], v[3]), maxOf(v[0], v[2]))
        }
        val kind = TrackWords.kind(name, "${p.str("osm_key") ?: ""}:${p.str("osm_value") ?: ""}", box) ?: return null
        val place = listOfNotNull(p.str("city") ?: p.str("county") ?: p.str("state"), p.str("country")).joinToString(", ")
        return TrackCandidate("${p.str("osm_type")}${p["osm_id"]?.jsonPrimitive?.longOrNull}", name, kind,
            Coord(c[1].jsonPrimitive.doubleOrNull ?: 0.0, c[0].jsonPrimitive.doubleOrNull ?: 0.0), place, box)
    }
}

/** Tag-based search and track layouts from the public Overpass API, every mirror at once. */
object Overpass {
    private val endpoints = listOf("https://overpass-api.de/api/interpreter", "https://overpass.private.coffee/api/interpreter")

    suspend fun run(query: String, timeoutMs: Int): List<JsonObject> {
        val form = "data=" + Net.enc(query)
        val tries = endpoints.map { url ->
            suspend {
                val text = Net.post(url, form, timeoutMs)
                val o = Files.json.parseToJsonElement(text).jsonObject
                // A busy server answers 200 with a timeout remark and whatever it found so far.
                val remark = o["remark"]?.jsonPrimitive?.contentOrNull
                if (remark != null && remark.contains("error", ignoreCase = true)) null
                else o["elements"]?.jsonArray?.map { it.jsonObject }
            }
        }
        return firstAnswer(*tries.toTypedArray()) ?: throw FinderBusy()
    }

    /** Motorsport venues around a point, from their tags. */
    suspend fun nearby(c: Coord, radiusKm: Double): List<TrackCandidate> {
        val r = (radiusKm * 1000).toInt()
        val query = """
            [out:json][timeout:40];
            (
              nwr["sport"~"motor|karting|motocross|speedway"]["name"](around:$r,${c.lat},${c.lon});
              way["highway"="raceway"]["name"](around:$r,${c.lat},${c.lon});
            );
            out tags bb 150;
        """.trimIndent()
        return run(query, 75_000).mapNotNull { candidate(it) }
    }

    /** The raceway ways inside a box, with the circuit relations they belong to. */
    suspend fun raceways(box: GeoBox): RacewayData {
        val query = """
            [out:json][timeout:50];
            way["highway"="raceway"](${box.minLat},${box.minLon},${box.maxLat},${box.maxLon})->.w;
            rel(bw.w)["type"="circuit"]->.r;
            (.w;.r;);
            out geom;
        """.trimIndent()
        val elements = run(query, 60_000)
        val ways = ArrayList<RacewayData.Way>()
        val circuits = ArrayList<RacewayData.Circuit>()
        for (e in elements) {
            val type = e["type"]?.jsonPrimitive?.contentOrNull
            if (type == "way") {
                val geom = e["geometry"] as? JsonArray ?: continue
                val pts = geom.mapNotNull { g ->
                    val o = g as? JsonObject ?: return@mapNotNull null
                    val lat = o["lat"]?.jsonPrimitive?.doubleOrNull
                    val lon = o["lon"]?.jsonPrimitive?.doubleOrNull
                    if (lat != null && lon != null) Coord(lat, lon) else null
                }
                if (pts.size < 2) continue
                val ids = (e["nodes"] as? JsonArray)?.mapNotNull { it.jsonPrimitive.longOrNull } ?: emptyList()
                ways.add(RacewayData.Way(e["id"]?.jsonPrimitive?.longOrNull ?: 0, if (ids.size == pts.size) ids else emptyList(), pts, tags(e)))
            } else if (type == "relation") {
                val members = (e["members"] as? JsonArray)?.map { it.jsonObject } ?: emptyList()
                fun node(role: String): Coord? {
                    val m = members.firstOrNull { it["type"]?.jsonPrimitive?.contentOrNull == "node" && it["role"]?.jsonPrimitive?.contentOrNull == role } ?: return null
                    val lat = m["lat"]?.jsonPrimitive?.doubleOrNull ?: return null
                    val lon = m["lon"]?.jsonPrimitive?.doubleOrNull ?: return null
                    return Coord(lat, lon)
                }
                fun role(m: JsonObject) = m["role"]?.jsonPrimitive?.contentOrNull ?: ""
                val wayMembers = members.filter { it["type"]?.jsonPrimitive?.contentOrNull == "way" }
                circuits.add(
                    RacewayData.Circuit(
                        name = tags(e)["name"] ?: "",
                        lap = wayMembers.filter { role(it).isEmpty() }.mapNotNull { it["ref"]?.jsonPrimitive?.longOrNull },
                        pits = wayMembers.filter { role(it) in listOf("pit_lane", "pit", "pitlane") }.mapNotNull { it["ref"]?.jsonPrimitive?.longOrNull },
                        start = node("start"), finish = node("finish"),
                    ),
                )
            }
        }
        return RacewayData(ways, circuits)
    }

    private fun tags(e: JsonObject): Map<String, String> =
        (e["tags"] as? JsonObject)?.mapValues { it.value.jsonPrimitive.contentOrNull ?: "" } ?: emptyMap()

    private fun candidate(e: JsonObject): TrackCandidate? {
        val tags = tags(e)
        val name = tags["name"]?.takeIf { it.isNotEmpty() } ?: return null
        var box: GeoBox? = null
        val center: Coord
        val b = e["bounds"] as? JsonObject
        if (b != null) {
            val bx = GeoBox(b["minlat"]!!.jsonPrimitive.doubleOrNull!!, b["minlon"]!!.jsonPrimitive.doubleOrNull!!,
                b["maxlat"]!!.jsonPrimitive.doubleOrNull!!, b["maxlon"]!!.jsonPrimitive.doubleOrNull!!)
            box = bx
            center = bx.center
        } else {
            val lat = e["lat"]?.jsonPrimitive?.doubleOrNull ?: return null
            val lon = e["lon"]?.jsonPrimitive?.doubleOrNull ?: return null
            center = Coord(lat, lon)
        }
        val sport = tags["sport"] ?: ""
        val kind = when {
            tags["highway"] == "raceway" -> TrackWords.kind(name, "highway:raceway", box) ?: return null
            sport.contains("karting") || name.contains("kart", ignoreCase = true) -> TrackCandidate.Kind.karting
            sport.contains("motocross") -> TrackCandidate.Kind.other
            else -> TrackCandidate.Kind.circuit
        }
        return TrackCandidate("${e["type"]?.jsonPrimitive?.contentOrNull}/${e["id"]?.jsonPrimitive?.longOrNull}", name, kind, center,
            tags["addr:city"] ?: "", box)
    }
}

/** The main OpenStreetMap API: fast for a small box, used when every Overpass server is busy. */
object OsmMap {
    suspend fun raceways(box: GeoBox): RacewayData {
        // The API refuses boxes over 0.25 square degrees; a circuit needs far less.
        if (box.area >= 0.02) throw FinderBusy()
        val url = "https://api.openstreetmap.org/api/0.6/map?bbox=${box.minLon},${box.minLat},${box.maxLon},${box.maxLat}"
        return Net.getStream(url, 60_000) { parse(it) }
    }

    private fun parse(input: InputStream): RacewayData {
        val nodes = HashMap<Long, Coord>()
        val found = ArrayList<Triple<Long, List<Long>, Map<String, String>>>()
        val relations = ArrayList<Pair<Map<String, String>, List<Triple<String, Long, String>>>>()
        var element = ""
        var elementID = 0L
        var refs = ArrayList<Long>()
        var tags = HashMap<String, String>()
        var members = ArrayList<Triple<String, Long, String>>()
        val p = Xml.newPullParser()
        p.setInput(input, "UTF-8")
        var ev = p.eventType
        while (ev != XmlPullParser.END_DOCUMENT) {
            if (ev == XmlPullParser.START_TAG) {
                fun a(n: String): String? = p.getAttributeValue(null, n)
                when (p.name) {
                    "node" -> {
                        val id = a("id")?.toLongOrNull()
                        val lat = a("lat")?.toDoubleOrNull()
                        val lon = a("lon")?.toDoubleOrNull()
                        if (id != null && lat != null && lon != null) nodes[id] = Coord(lat, lon)
                    }
                    "way", "relation" -> {
                        element = p.name
                        elementID = a("id")?.toLongOrNull() ?: 0
                        refs = ArrayList()
                        tags = HashMap()
                        members = ArrayList()
                    }
                    "nd" -> if (element == "way") a("ref")?.toLongOrNull()?.let { refs.add(it) }
                    "member" -> if (element == "relation") {
                        val type = a("type")
                        val ref = a("ref")?.toLongOrNull()
                        if (type != null && ref != null) members.add(Triple(type, ref, a("role") ?: ""))
                    }
                    "tag" -> if (element.isNotEmpty()) {
                        val k = a("k")
                        val v = a("v")
                        if (k != null && v != null) tags[k] = v
                    }
                }
            } else if (ev == XmlPullParser.END_TAG) {
                if (p.name == "way" && tags["highway"] == "raceway") found.add(Triple(elementID, refs, tags))
                if (p.name == "relation") relations.add(tags to members)
                if (p.name == "way" || p.name == "relation") element = ""
            }
            ev = p.next()
        }
        val ways = found.mapNotNull { (id, r, t) ->
            val pts = r.mapNotNull { nodes[it] }
            if (pts.size < 2) null else RacewayData.Way(id, if (pts.size == r.size) r else emptyList(), pts, t)
        }
        val circuits = relations.filter { it.first["type"] == "circuit" }.map { (t, m) ->
            fun node(role: String) = m.firstOrNull { it.first == "node" && it.third == role }?.let { nodes[it.second] }
            RacewayData.Circuit(
                name = t["name"] ?: "",
                lap = m.filter { it.first == "way" && it.third.isEmpty() }.map { it.second },
                pits = m.filter { it.first == "way" && it.third in listOf("pit_lane", "pit", "pitlane") }.map { it.second },
                start = node("start"), finish = node("finish"),
            )
        }
        return RacewayData(ways, circuits)
    }
}

object TrackFinder {
    /** One entry per venue: a circuit found twice shows once, keeping the one with the larger area. */
    fun merge(list: List<TrackCandidate>): List<TrackCandidate> {
        val out = ArrayList<TrackCandidate>()
        for (c in list) {
            val i = out.indexOfFirst { same(it, c) }
            if (i >= 0) {
                if ((c.box?.area ?: 0.0) > (out[i].box?.area ?: 0.0)) out[i] = c
                continue
            }
            out.add(c)
        }
        return out
    }

    fun same(a: TrackCandidate, b: TrackCandidate): Boolean {
        if (a.kind != b.kind) return false
        val d = Geo.distance(a.center, b.center)
        if (a.name.lowercase() == b.name.lowercase()) return d < 5000
        if (d < 400) return true
        return (a.box?.padded(200.0)?.contains(b.center) ?: false) || (b.box?.padded(200.0)?.contains(a.center) ?: false)
    }

    fun sorted(list: List<TrackCandidate>, from: Coord): List<TrackCandidate> =
        list.map { it.copy(distanceKm = Geo.distance(from, it.center) / 1000) }.sortedBy { it.distanceKm ?: 0.0 }

    /**
     * The raceways of a venue with its circuit relations. Overpass and the OpenStreetMap API race each
     * other (the API a moment later); the first answer wins. Null when neither answers.
     */
    suspend fun raceways(box: GeoBox): RacewayData? = firstAnswer(
        { Overpass.raceways(box) },
        { delay(1500); OsmMap.raceways(box) },
    )

    /** A new track from what OpenStreetMap has in the box: the outline, and the lines put in place. */
    suspend fun track(name: String, place: String, center: Coord, box: GeoBox, karting: Boolean): Track {
        val data = raceways(box) ?: RacewayData()
        val t = Track(name = name, place = place, center = center, outline = data.outline)
        val layouts = withContext(Dispatchers.Default) { AutoLines.layouts(data, if (karting) 14.0 else 24.0) }
        return t.applyAuto(layouts)
    }
}
