import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../domain/unidad_mapa.dart';

/// Mapa operativo. Dibuja SOLO las unidades con geometría real.
/// Sin ninguna geometría muestra "sin datos", no un mapa inventado.
/// Color por tipo (preferencias del proyecto): potrero/ganadería → rojo,
/// infraestructura → amarillo, agroecología → verde. Los tipos reales de
/// `unidades_espaciales.tipo` no están confirmados: lo desconocido va en gris.
class MapaPantalla extends StatelessWidget {
  const MapaPantalla({super.key, required this.unidades, this.alTocar});
  final List<UnidadMapa> unidades;
  final void Function(UnidadMapa)? alTocar;

  @override
  Widget build(BuildContext context) {
    final dibujables = unidades.where((u) => u.tieneGeometria).toList();
    final caja = cajaDe(dibujables);
    if (caja == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            unidades.isEmpty
                ? 'Sin datos: aún no hay unidades espaciales registradas.'
                : 'Sin datos: ${unidades.length} unidad(es) registradas, ninguna con geometría (pendiente de levantamiento).',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final limites = LatLngBounds(LatLng(caja.sur, caja.oeste), LatLng(caja.norte, caja.este));
    return FlutterMap(
      options: MapOptions(
        initialCameraFit: CameraFit.bounds(bounds: limites, padding: const EdgeInsets.all(24)),
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
              color: _color(u).withOpacity(0.25),
              borderColor: _color(u),
              borderStrokeWidth: u.esTemporal ? 1.5 : 2.5,
              pattern: u.esTemporal ? StrokePattern.dashed(segments: const [6, 4]) : const StrokePattern.solid(),
            ),
        ]),
      ],
    );
  }

  Color _color(UnidadMapa u) => switch (u.tipo) {
        'potrero' || 'lote' => Colors.red,
        'infraestructura' => Colors.amber,
        'agroecologia' || 'vivero' || 'pancoger' => Colors.green,
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
