import 'dart:convert';

/// Coordenada (latitud, longitud) en WGS84.
class Punto {
  const Punto(this.lat, this.lon);
  final double lat;
  final double lon;
}

/// Unidad espacial lista para dibujar. [anillo] es null cuando NO hay geometría
/// ("sin datos"): nunca se dibuja ni se inventa nada en ese caso.
class UnidadMapa {
  const UnidadMapa({
    required this.id,
    required this.tipo,
    required this.nombre,
    required this.esTemporal,
    this.anillo,
    this.naturaleza,
    this.areaM2Calculada,
  });
  final String id;
  final String tipo;
  final String? nombre;
  final bool esTemporal;
  final List<Punto>? anillo; // anillo exterior del polígono
  final String? naturaleza; // declarada: medido, estimado, ...
  final double? areaM2Calculada; // CALCULADA por el servidor

  bool get tieneGeometria => anillo != null && anillo!.length >= 4;
}

/// Convierte el texto GeoJSON (Polygon) de la vista `v_unidades_mapa`.
/// Devuelve null si el texto falta o no es un polígono utilizable; nunca lanza
/// ni rellena valores: un dato ilegible es "sin datos".
List<Punto>? anilloDesdeGeoJson(String? geojson) {
  if (geojson == null || geojson.trim().isEmpty) return null;
  try {
    final j = jsonDecode(geojson);
    if (j is! Map || j['type'] != 'Polygon') return null;
    final anillos = j['coordinates'];
    if (anillos is! List || anillos.isEmpty) return null;
    final exterior = anillos.first;
    if (exterior is! List) return null;
    final puntos = <Punto>[];
    for (final c in exterior) {
      if (c is! List || c.length < 2) return null;
      final lon = c[0], lat = c[1]; // GeoJSON es [lon, lat]
      if (lon is! num || lat is! num) return null;
      puntos.add(Punto(lat.toDouble(), lon.toDouble()));
    }
    return puntos.length >= 4 ? puntos : null;
  } catch (_) {
    return null;
  }
}

/// Construye una [UnidadMapa] desde una fila de la vista.
UnidadMapa unidadDesdeFila(Map<String, Object?> f) => UnidadMapa(
      id: f['id'] as String,
      tipo: (f['tipo'] as String?) ?? 'desconocido',
      nombre: f['nombre'] as String?,
      esTemporal: (f['es_temporal'] as bool?) ?? false,
      anillo: anilloDesdeGeoJson(f['geometria_geojson'] as String?),
      naturaleza: f['geometria_naturaleza'] as String?,
      areaM2Calculada: (f['area_m2_calculada'] as num?)?.toDouble(),
    );

/// Caja envolvente [sur, oeste, norte, este] de las unidades con geometría.
/// Null si ninguna tiene geometría.
({double sur, double oeste, double norte, double este})? cajaDe(Iterable<UnidadMapa> us) {
  double? s, o, n, e;
  for (final u in us) {
    if (!u.tieneGeometria) continue;
    for (final p in u.anillo!) {
      s = s == null || p.lat < s ? p.lat : s;
      n = n == null || p.lat > n ? p.lat : n;
      o = o == null || p.lon < o ? p.lon : o;
      e = e == null || p.lon > e ? p.lon : e;
    }
  }
  if (s == null) return null;
  return (sur: s, oeste: o!, norte: n!, este: e!);
}
