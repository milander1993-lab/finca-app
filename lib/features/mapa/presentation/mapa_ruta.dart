import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tema.dart';
import '../../../core/finca_actual.dart';
import '../../../core/supabase.dart';
import '../../../core/widgets.dart';
import '../domain/unidad_mapa.dart';
import 'mapa_pantalla.dart';

class DatosMapa {
  const DatosMapa(this.unidades, this.puntos, this.sinUbicacion);
  final List<UnidadMapa> unidades;
  final List<PuntoMapa> puntos;
  final List<Map<String, dynamic>> sinUbicacion;
}

final datosMapaProvider = FutureProvider.autoDispose<DatosMapa>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const DatosMapa([], [], []);
  final db = ref.watch(supabaseProvider);
  final u = await db.from('v_unidades_mapa').select().eq('finca_id', finca.id);
  final agua = await db.from('fuentes_agua').select('id, nombre, tipo, latitud, longitud').eq('finca_id', finca.id).eq('is_deleted', false);
  final infra = await db.from('infraestructuras').select('id, nombre, tipo, latitud, longitud').eq('finca_id', finca.id).eq('is_deleted', false);
  final puntos = <PuntoMapa>[];
  final sin = <Map<String, dynamic>>[];
  void agregar(List<Map<String, dynamic>> filas, String tabla, Color color, IconData icono) {
    for (final f in filas) {
      final lat = (f['latitud'] as num?)?.toDouble();
      final lon = (f['longitud'] as num?)?.toDouble();
      if (lat == null || lon == null) {
        sin.add({...f, 'tabla': tabla});
      } else {
        puntos.add(PuntoMapa(id: '${f['id']}', tabla: tabla, nombre: '${f['nombre']}', lat: lat, lon: lon, color: color, icono: icono));
      }
    }
  }

  agregar(List<Map<String, dynamic>>.from(agua), 'fuentes_agua', ColoresArea.agroecologia, Icons.water_drop);
  agregar(List<Map<String, dynamic>>.from(infra), 'infraestructuras', ColoresArea.infraestructura, Icons.home_work);
  return DatosMapa([for (final f in u) unidadDesdeFila(f)], puntos, sin);
});

/// Mapa ↔ resumen: tocar una unidad o un punto abre su información (§45, §48).
class MapaRuta extends ConsumerWidget {
  const MapaRuta({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = ref.watch(datosMapaProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Mapa operativo')),
      body: d.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (datos) => Column(children: [
          Expanded(
            flex: 3,
            child: MapaPantalla(
              unidades: datos.unidades,
              puntos: datos.puntos,
              alTocar: (_) => context.push('/potreros'),
              alTocarPunto: (p) => context.push('/e/${p.tabla}/${p.id}'),
            ),
          ),
          Expanded(
            flex: 2,
            child: ListView(padding: const EdgeInsets.all(12), children: [
              Text(
                'Cartografía operativa: no equivale a levantamiento legal, topográfico ni geodésico. '
                'Unidades: ${datos.unidades.length} (con geometría: ${datos.unidades.where((u) => u.tieneGeometria).length}) · '
                'Puntos ubicados: ${datos.puntos.length}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (datos.sinUbicacion.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Sin ubicación todavía (toque para agregar latitud y longitud):',
                    style: Theme.of(context).textTheme.titleSmall),
                for (final f in datos.sinUbicacion)
                  ListTile(
                    dense: true,
                    leading: Icon(f['tabla'] == 'fuentes_agua' ? Icons.water_drop : Icons.home_work),
                    title: Text('${f['nombre']}'),
                    subtitle: Text('${f['tipo']} · sin datos de ubicación'),
                    onTap: () => context.push('/e/${f['tabla']}/${f['id']}/editar'),
                  ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}
