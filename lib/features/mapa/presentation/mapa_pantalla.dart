import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/tema.dart';
import '../domain/unidad_mapa.dart';

/// Punto georreferenciado (nacimiento, infraestructura…) que se dibuja como marcador.
class PuntoMapa {
  const PuntoMapa({required this.id, required this.tabla, required this.nombre, required this.lat, required this.lon, required this.color, required this.icono});
  final String id;
  final String tabla;
  final String nombre;
  final double lat;
  final double lon;
  final Color color;
  final IconData icono;
}

/// Mapa operativo (§45). Dibuja SOLO las unidades con geometría real y los puntos
/// con coordenadas. Sin nada georreferenciado muestra "sin datos", no un mapa inventado.
/// Es cartografía operativa: no equivale a levantamiento legal, topográfico ni geodésico.
class MapaPantalla extends StatelessWidget {
  const MapaPantalla({super.key, required this.unidades, this.puntos = const [], this.alTocar, this.alTocarPunto});
  final List<UnidadMapa> unidades;
  final List<PuntoMapa> puntos;
  final void Function(UnidadMapa)? alTocar;
  final void Function(PuntoMapa)? alTocarPunto;

  @override
  Widget build(BuildContext context) {
    final dibujables = unidades.where((u) => u.tieneGeometria).toList();
    final caja = cajaDe(dibujables);
    double? s = caja?.sur, o = caja?.oeste, n = caja?.norte, e = caja?.este;
    for (final p in puntos) {
      s = s == null || p.lat < s ? p.lat : s;
      n = n == null || p.lat > n ? p.lat : n;
      o = o == null || p.lon < o ? p.lon : o;
      e = e == null || p.lon > e ? p.lon : e;
    }
    if (s == null || n == null || o == null || e == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            unidades.isEmpty
                ? 'Sin datos: aún no hay unidades espaciales ni puntos georreferenciados.'
                : 'Sin datos: ${unidades.length} unidad(es) registradas, ninguna con geometría (pendiente de levantamiento). '
                    'Puede ubicar nacimientos e infraestructura con latitud y longitud en sus fichas.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // Un solo punto: se abre una pequeña caja alrededor para poder encuadrar.
    if (s == n) {
      s = s - 0.001;
      n = n + 0.001;
    }
    if (o == e) {
      o = o - 0.001;
      e = e + 0.001;
    }
    final limites = LatLngBounds(LatLng(s, o), LatLng(n, e));
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(bounds: limites, padding: const EdgeInsets.all(32)),
        onTap: (_, punto) => _tocar(punto, dibujables),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'co.finca.app', // PENDIENTE 34.8: proveedor de mapas y modo offline
        ),
        PolygonLayer(polygons: [
          for (final u in dibujables)
            Polygon(
              points: [for (final p in u.anillo!) LatLng(p.lat, p.lon)],
              color: _color(u).withAlpha(64),
              borderColor: _color(u),
              borderStrokeWidth: u.esTemporal ? 1.5 : 2.5,
              pattern: u.esTemporal ? StrokePattern.dashed(segments: const [6, 4]) : const StrokePattern.solid(),
            ),
        ]),
        MarkerLayer(markers: [
          for (final p in puntos)
            Marker(
              point: LatLng(p.lat, p.lon),
              width: 40,
              height: 40,
              child: GestureDetector(
                onTap: alTocarPunto == null ? null : () => alTocarPunto!(p),
                child: Tooltip(message: p.nombre, child: Icon(p.icono, color: p.color, size: 32)),
              ),
            ),
        ]),
      ],
    );
  }

  Color _color(UnidadMapa u) => switch (u.tipo) {
        'potrero' || 'division' || 'lote' => ColoresArea.ganaderia,
        'infraestructura' => ColoresArea.infraestructura,
        'agroecologia' || 'vivero' || 'pancoger' || 'bosque' || 'humedal' => ColoresArea.agroecologia,
        _ => Colors.grey,
      };

  void _tocar(LatLng p, List<UnidadMapa> us) {
    if (alTocar == null) return;
    for (final u in us.reversed) {
      if (_contiene(u.anillo!, p.latitude, p.longitude)) {
        alTocar!(u);
        return;
      }
    }
  }

  /// Punto en polígono (trazado de rayos).
  bool _contiene(List<Punto> a, double lat, double lon) {
    var dentro = false;
    for (var i = 0, j = a.length - 1; i < a.length; j = i++) {
      final cruza = (a[i].lat > lat) != (a[j].lat > lat) &&
          lon < (a[j].lon - a[i].lon) * (lat - a[i].lat) / (a[j].lat - a[i].lat) + a[i].lon;
      if (cruza) dentro = !dentro;
    }
    return dentro;
  }
}
