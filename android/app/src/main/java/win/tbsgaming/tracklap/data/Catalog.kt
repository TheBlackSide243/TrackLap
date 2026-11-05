package win.tbsgaming.tracklap.data

import win.tbsgaming.tracklap.model.Coord
import win.tbsgaming.tracklap.model.GeoBox
import java.text.Normalizer
import java.util.Locale

/**
 * Well-known circuits, shown before any search and matched while typing. Positions and areas come
 * from OpenStreetMap (looked up on Photon); the layout is downloaded when one is picked.
 */
object Catalog {
    private val ci = TrackCandidate.Kind.circuit
    private val ka = TrackCandidate.Kind.karting

    val all: List<TrackCandidate> by lazy {
        listOf(
            c("Autodromo Nazionale Monza", "Monza", "IT", ci, 45.61911, 9.28264, GeoBox(45.6080, 9.2740, 45.6330, 9.2970)),
            c("Autodromo del Mugello", "Scarperia e San Piero", "IT", ci, 43.99938, 11.37236, GeoBox(43.98993, 11.36338, 44.00923, 11.37994)),
            c("Autodromo Enzo e Dino Ferrari", "Imola", "IT", ci, 44.34099, 11.71190, GeoBox(44.33570, 11.70096, 44.34631, 11.72613)),
            c("Misano World Circuit Marco Simoncelli", "Misano Adriatico", "IT", ci, 43.96218, 12.68403, GeoBox(43.95736, 12.67586, 43.96713, 12.69157)),
            c("Autodromo di Vallelunga", "Campagnano di Roma", "IT", ci, 42.16097, 12.36986, GeoBox(42.15415, 12.36663, 42.16764, 12.37414)),
            c("Autodromo Riccardo Paletti", "Varano de' Melegari", "IT", ci, 44.68063, 10.02103, GeoBox(44.67881, 10.01644, 44.68234, 10.03027)),
            c("Autodromo di Franciacorta", "Castrezzato", "IT", ci, 45.51267, 10.00550, GeoBox(45.50718, 9.99977, 45.51723, 10.01090)),
            c("Adria International Raceway", "Adria", "IT", ci, 45.04391, 12.14746, GeoBox(45.04104, 12.14521, 45.04671, 12.15005)),
            c("Autodromo dell'Umbria", "Magione", "IT", ci, 43.13069, 12.23882, GeoBox(43.12619, 12.23511, 43.13457, 12.24227)),
            c("Cremona Circuit", "San Martino del Lago", "IT", ci, 45.08544, 10.31046, GeoBox(45.08297, 10.30097, 45.08780, 10.31621)),
            c("Autodromo di Modena", "Modena", "IT", ci, 44.63374, 10.81405, GeoBox(44.63086, 10.80932, 44.63623, 10.81859)),
            c("Autodromo di Pergusa", "Enna", "IT", ci, 37.52042, 14.30464, GeoBox(37.50710, 14.29774, 37.52262, 14.31462)),
            c("Autodromo del Levante", "Binetto", "IT", ci, 40.99450, 16.74134, GeoBox(40.99196, 16.73954, 40.99705, 16.74408)),
            c("South Garda Karting", "Lonato del Garda", "IT", ka, 45.42502, 10.50606, GeoBox(45.42360, 10.50485, 45.42649, 10.50805)),
            c("Adria Karting Raceway", "Adria", "IT", ka, 45.04579, 12.15092, GeoBox(45.04475, 12.14955, 45.04680, 12.15195)),
            c("Kartodromo Pista Azzurra", "Borgo Ticino", "IT", ka, 45.70085, 8.59426, GeoBox(45.69963, 8.59271, 45.70215, 8.59595)),
            c("Circuit de Spa-Francorchamps", "Stavelot", "BE", ci, 50.43693, 5.97013, GeoBox(50.42685, 5.95663, 50.44708, 5.97920)),
            c("Nürburgring", "Nürburg", "DE", ci, 50.33092, 6.94067, GeoBox(50.32277, 6.93266, 50.33896, 6.95209)),
            c("Nürburgring Nordschleife", "Nürburg", "DE", ci, 50.35500, 6.96500, GeoBox(50.3200, 6.9200, 50.3880, 7.0100)),
            c("Hockenheimring", "Hockenheim", "DE", ci, 49.32980, 8.57630, GeoBox(49.32479, 8.56317, 49.33487, 8.58578)),
            c("Sachsenring", "Hohenstein-Ernstthal", "DE", ci, 50.79118, 12.69318, GeoBox(50.78800, 12.67872, 50.79433, 12.69757)),
            c("Lausitzring", "Schipkau", "DE", ci, 51.53432, 13.93212, GeoBox(51.52666, 13.91806, 51.54404, 13.94316)),
            c("Red Bull Ring", "Spielberg", "AT", ci, 47.22213, 14.76432, GeoBox(47.21842, 14.75161, 47.22811, 14.77166)),
            c("Salzburgring", "Koppl", "AT", ci, 47.82249, 13.15606, GeoBox(47.82036, 13.15249, 47.82462, 13.17744)),
            c("Silverstone Circuit", "Silverstone", "GB", ci, 52.07181, -1.01430, GeoBox(52.06214, -1.02565, 52.08161, -1.00624)),
            c("Brands Hatch", "Fawkham", "GB", ci, 51.35749, 0.26001, GeoBox(51.35186, 0.25251, 51.36312, 0.26948)),
            c("Donington Park", "Castle Donington", "GB", ci, 52.82835, -1.37929, GeoBox(52.82220, -1.39599, 52.83375, -1.36292)),
            c("Circuit de Barcelona-Catalunya", "Montmeló", "ES", ci, 41.56879, 2.25744, GeoBox(41.56212, 2.25125, 41.57552, 2.26496)),
            c("Circuito de Jerez", "Jerez de la Frontera", "ES", ci, 36.70780, -6.03251, GeoBox(36.70228, -6.03924, 36.71394, -6.02547)),
            c("Circuit Ricardo Tormo", "Cheste", "ES", ci, 39.48581, -0.62864, GeoBox(39.48092, -0.63659, 39.49059, -0.62163)),
            c("MotorLand Aragón", "Alcañiz", "ES", ci, 41.07782, -0.19496, GeoBox(41.06856, -0.21565, 41.08747, -0.17676)),
            c("Circuito de Navarra", "Los Arcos", "ES", ci, 42.56118, -2.16498, GeoBox(42.55479, -2.17105, 42.56758, -2.15786)),
            c("Circuito del Jarama", "San Sebastián de los Reyes", "ES", ci, 40.61582, -3.58489, GeoBox(40.61073, -3.59301, 40.62105, -3.58093)),
            c("Circuit Paul Ricard", "Le Castellet", "FR", ci, 43.25250, 5.79430, GeoBox(43.24639, 5.77749, 43.25886, 5.80497)),
            c("Circuit de Nevers Magny-Cours", "Magny-Cours", "FR", ci, 46.86375, 3.16621, GeoBox(46.85840, 3.15878, 46.86913, 3.17030)),
            c("Circuit Bugatti", "Le Mans", "FR", ci, 47.95550, 0.21200, GeoBox(47.9480, 0.2030, 47.9620, 0.2240)),
            c("Circuit Dijon-Prenois", "Prenois", "FR", ci, 47.36308, 4.90016, GeoBox(47.35738, 4.89132, 47.36863, 4.90633)),
            c("Circuit Zandvoort", "Zandvoort", "NL", ci, 52.38781, 4.54626, GeoBox(52.38312, 4.53555, 52.39250, 4.55429)),
            c("TT Circuit Assen", "Assen", "NL", ci, 52.95950, 6.52414, GeoBox(52.95121, 6.50904, 52.96771, 6.53484)),
            c("Autódromo Internacional do Algarve", "Portimão", "PT", ci, 37.23036, -8.62735, GeoBox(37.22320, -8.63310, 37.23750, -8.62267)),
            c("Circuito do Estoril", "Alcabideche", "PT", ci, 38.75060, -9.39420, GeoBox(38.7430, -9.4040, 38.7580, -9.3850)),
            c("Hungaroring", "Mogyoród", "HU", ci, 47.58265, 19.25002, GeoBox(47.57541, 19.24070, 47.58941, 19.25997)),
            c("Masarykův okruh", "Brno", "CZ", ci, 49.20500, 16.45200, GeoBox(49.1990, 16.4370, 49.2120, 16.4670)),
            c("Autodrom Most", "Most", "CZ", ci, 50.51822, 13.59791, GeoBox(50.51437, 13.58924, 50.52207, 13.61564)),
            c("Slovakia Ring", "Orechová Potôň", "SK", ci, 48.05462, 17.56486, GeoBox(48.04807, 17.55818, 48.06175, 17.57572)),
            c("Tor Poznań", "Przeźmierowo", "PL", ci, 52.41824, 16.80691, GeoBox(52.41406, 16.79750, 52.42252, 16.81529)),
            c("Suzuka Circuit", "Suzuka", "JP", ci, 34.84361, 136.53423, GeoBox(34.83809, 136.52065, 34.84939, 136.54416)),
            c("Fuji Speedway", "Oyama", "JP", ci, 35.37148, 138.93164, GeoBox(35.36358, 138.91662, 35.37892, 138.93903)),
            c("Circuit of The Americas", "Austin", "US", ci, 30.13563, -97.63662, GeoBox(30.12169, -97.65012, 30.14954, -97.61664)),
            c("WeatherTech Raceway Laguna Seca", "Monterey", "US", ci, 36.58441, -121.75339, GeoBox(36.57944, -121.75836, 36.58922, -121.74842)),
            c("Road America", "Elkhart Lake", "US", ci, 43.79917, -87.99232, GeoBox(43.79028, -88.00648, 43.80833, -87.98183)),
            c("Watkins Glen International", "Watkins Glen", "US", ci, 42.33638, -76.92505, GeoBox(42.32552, -76.93064, 42.34725, -76.91688)),
            c("Circuit Gilles-Villeneuve", "Montréal", "CA", ci, 45.50480, -73.52620, GeoBox(45.4955, -73.5320, 45.5140, -73.5190)),
            c("Autódromo José Carlos Pace", "São Paulo", "BR", ci, -23.70182, -46.69692, GeoBox(-23.70733, -46.70120, -23.69606, -46.69159)),
            c("Autódromo Hermanos Rodríguez", "Ciudad de México", "MX", ci, 19.40420, -99.09070, GeoBox(19.3960, -99.1000, 19.4120, -99.0800)),
            c("Yas Marina Circuit", "Abu Dhabi", "AE", ci, 24.47185, 54.60580, GeoBox(24.46219, 54.60072, 24.48152, 54.61001)),
            c("Bahrain International Circuit", "Sakhir", "BH", ci, 26.03250, 50.51060, GeoBox(26.0220, 50.5000, 26.0420, 50.5230)),
            c("Sepang International Circuit", "Sepang", "MY", ci, 2.75997, 101.73692, GeoBox(2.75256, 101.72385, 2.76716, 101.74903)),
            c("Phillip Island Grand Prix Circuit", "Phillip Island", "AU", ci, -38.50408, 145.23455, GeoBox(-38.51136, 145.22955, -38.49678, 145.23874)),
            c("Mount Panorama Circuit", "Bathurst", "AU", ci, -33.44850, 149.55600, GeoBox(-33.4670, 149.5360, -33.4350, 149.5690)),
            c("Kyalami", "Midrand", "ZA", ci, -25.99702, 28.06783, GeoBox(-26.00154, 28.05916, -25.99250, 28.07601)),
        )
    }

    /** The catalog with the circuits of your own country first. */
    val forYou: List<TrackCandidate>
        get() {
            val home = Locale.getDefault().country
            return all.filter { it.country == home } + all.filter { it.country != home }
        }

    fun matching(q: String): List<TrackCandidate> {
        val words = q.split(" ").filter { it.isNotBlank() }.map(::fold)
        if (words.isEmpty()) return forYou
        return forYou.filter { c -> words.all { fold(c.name).contains(it) || fold(c.place).contains(it) } }
    }

    /** Lower case without accents, as a search compares names. */
    private fun fold(s: String) = Normalizer.normalize(s, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").lowercase()

    private fun c(name: String, city: String, cc: String, kind: TrackCandidate.Kind, lat: Double, lon: Double, box: GeoBox): TrackCandidate {
        val country = Locale("", cc).displayCountry.ifEmpty { cc }
        return TrackCandidate("catalog-$cc-$name", name, kind, Coord(lat, lon), "$city, $country", box, cc)
    }
}
