import 'dart:convert';
import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tema.dart';
import '../../core/entidades/definicion.dart';
import '../../core/entidades/repo_generico.dart';
import '../../core/finca_actual.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';
import '../ia/ia.dart';

/// Informes y tablero (§48): vistas sobre datos existentes, por periodo, con
/// exportación. La IA puede interpretar, pero no completa datos.
class InformesPantalla extends ConsumerStatefulWidget {
  const InformesPantalla({super.key});
  @override
  ConsumerState<InformesPantalla> createState() => _InformesPantallaState();
}

class _InformesPantallaState extends ConsumerState<InformesPantalla> {
  int _dias = 30;

  PeriodoTablero get _periodo {
    final hoy = DateTime.now();
    final h = DateTime(hoy.year, hoy.month, hoy.day);
    return PeriodoTablero(h.subtract(Duration(days: _dias)), h);
  }

  List<MapEntry<String, num?>> _pares(Object? lista) => [
        for (final e in (lista as List?) ?? const [])
          MapEntry(etiquetaDe('${(e as Map)['etiqueta']}'), e['valor'] as num?),
      ];

  List<MapEntry<String, num>> _serie(Object? lista) => [
        for (final e in (lista as List?) ?? const [])
          if ((e as Map)['valor'] != null) MapEntry('${e['etiqueta']}', e['valor'] as num),
      ];

  Future<void> _exportar(Map<String, dynamic> d) async {
    final finca = ref.read(fincaActualProvider);
    final p = _periodo;
    final filas = <List<String>>[
      ['Informe de la finca', finca?.nombre ?? ''],
      ['Periodo', '${fechaIso(p.desde!)} a ${fechaIso(p.hasta!)}'],
      ['Generado', fechaCorta((d['periodo'] as Map?)?['generado_en'])],
      ['Regla', 'Vacío = sin datos (no es cero)'],
      [],
      ['Sección', 'Concepto', 'Valor', 'Unidad'],
    ];
    void agregar(String seccion, Object? lista, String unidad) {
      for (final e in _pares(lista)) {
        filas.add([seccion, e.key, e.value == null ? 'sin datos' : '${e.value}', unidad]);
      }
    }

    final animales = (d['animales'] as Map?) ?? const {};
    filas.add(['Ganadería', 'Animales activos', '${animales['total'] ?? 'sin datos'}', 'animales']);
    filas.add(['Ganadería', 'Animales con peso', '${animales['con_peso'] ?? 'sin datos'}', 'animales']);
    agregar('Ganadería por categoría', animales['por_categoria'], 'animales');
    agregar('Superficie por destino', ((d['territorio'] as Map?) ?? const {})['superficie_destinos'], 'ha');
    final lluvia = (d['lluvia'] as Map?) ?? const {};
    filas.add(['Clima', 'Lluvia del periodo', '${lluvia['total_mm'] ?? 'sin datos'}', 'mm (= L/m²)']);
    final leche = (d['leche'] as Map?) ?? const {};
    filas.add(['Leche', 'Producida', '${leche['total_litros'] ?? 'sin datos'}', 'L']);
    filas.add(['Leche', 'Entregada', '${leche['entregado_litros'] ?? 'sin datos'}', 'L']);
    filas.add(['Leche', 'Pagada', '${leche['pagado_cop'] ?? 'sin datos'}', 'COP']);
    agregar('Economía', d['economia'], 'COP');
    agregar('Actividades por estado', ((d['actividades'] as Map?) ?? const {})['por_estado'], 'actividades');
    agregar('Alertas abiertas por tipo', ((d['alertas'] as Map?) ?? const {})['por_tipo'], 'alertas');
    agregar('Decisiones por estado', d['decisiones_por_estado'], 'decisiones');
    agregar('Infraestructura por estado', d['infraestructura_por_estado'], 'elementos');
    for (final a in (d['aforos'] as List?) ?? const []) {
      final m = a as Map;
      filas.add(['Aforos', '${m['unidad'] ?? ''} ${fechaCorta(m['fecha'], hora: false)}',
        m['ms_pct'] == null ? 'no calculable' : '${m['ms_pct']}', '% MS']);
    }
    String celda(String s) => '"${s.replaceAll('"', '""')}"';
    final csv = filas.map((f) => f.map(celda).join(';')).join('\n');
    try {
      await FileSaver.instance.saveFile(
          name: 'informe_finca_${fechaIso(DateTime.now())}',
          bytes: Uint8List.fromList(utf8.encode('﻿$csv')),
          ext: 'csv',
          mimeType: MimeType.csv);
      if (mounted) mostrarMensaje(context, 'Informe descargado (CSV para Excel o Google Sheets).');
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(tableroProvider(_periodo));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Informes y tablero'),
        actions: [
          IconButton(
            tooltip: 'Interpretar con IA',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => AsistenteIA.abrir(context, funcion: 'analizar_finca', titulo: 'Informe del periodo'),
          ),
          if (t.valueOrNull != null)
            IconButton(tooltip: 'Exportar CSV', icon: const Icon(Icons.download), onPressed: () => _exportar(t.value!)),
        ],
      ),
      body: t.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (d) {
          final animales = Map<String, dynamic>.from((d['animales'] as Map?) ?? const {});
          final territorio = Map<String, dynamic>.from((d['territorio'] as Map?) ?? const {});
          final lluvia = Map<String, dynamic>.from((d['lluvia'] as Map?) ?? const {});
          final leche = Map<String, dynamic>.from((d['leche'] as Map?) ?? const {});
          final actividades = Map<String, dynamic>.from((d['actividades'] as Map?) ?? const {});
          final alertas = Map<String, dynamic>.from((d['alertas'] as Map?) ?? const {});
          final aforos = List<Map>.from((d['aforos'] as List?) ?? const []);
          final sistemas = List<Map>.from((d['sistemas'] as List?) ?? const []);
          final economia = _pares(d['economia']);
          final costos = economia.where((e) => e.key == 'Costo').map((e) => e.value ?? 0).fold<num>(0, (a, b) => a + b);
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(tableroProvider),
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 40), children: [
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 7, label: Text('7 d')),
                  ButtonSegment(value: 30, label: Text('30 d')),
                  ButtonSegment(value: 90, label: Text('90 d')),
                  ButtonSegment(value: 365, label: Text('1 año')),
                ],
                selected: {_dias},
                onSelectionChanged: (s) => setState(() => _dias = s.first),
              ),
              const SizedBox(height: 4),
              Text('Periodo: ${fechaIso(_periodo.desde!)} a ${fechaIso(_periodo.hasta!)} · vacío = sin datos (no es cero)',
                  style: Theme.of(context).textTheme.bodySmall),
              Seccion(
                titulo: 'Ganadería: animales por categoría',
                icono: Icons.pets,
                color: ColoresArea.ganaderia,
                hijos: [
                  BarrasHorizontales(datos: _pares(animales['por_categoria']), color: ColoresArea.ganaderia, unidad: 'anim.'),
                  const SizedBox(height: 4),
                  Text(
                    'Peso vivo registrado: ${valorONo(animales['peso_total_kg'] as num?, unidad: 'kg')} '
                    '(${animales['con_peso'] ?? 0} de ${animales['total'] ?? 0} animales con peso; '
                    '${(animales['con_peso'] ?? 0) == (animales['total'] ?? 0) ? 'completo' : 'incompleto: no se usa como total del hato'})',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              Seccion(
                titulo: 'Territorio: superficie por destino',
                icono: Icons.square_foot,
                color: ColoresArea.agroecologia,
                hijos: [
                  BarrasHorizontales(
                    datos: _pares(territorio['superficie_destinos']),
                    color: ColoresArea.agroecologia,
                    unidad: 'ha',
                    alTocar: (_) => context.push('/e/destinos_superficie'),
                  ),
                  Text(
                    'Naturaleza: ${[for (final s in (territorio['superficie_destinos'] as List?) ?? const []) '${(s as Map)['etiqueta']}: ${s['naturaleza']}'].join(' · ')}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text('Fuentes de agua: ${territorio['fuentes_agua'] ?? 0} (sin ubicación: ${territorio['fuentes_sin_ubicacion'] ?? 0}) · '
                      'Muestras de suelo: ${territorio['muestras_suelo'] ?? 0}'),
                ],
              ),
              Seccion(
                titulo: 'Sistemas productivos',
                icono: Icons.agriculture,
                color: ColoresArea.agroecologia,
                hijos: [
                  if (sistemas.isEmpty) const Text('sin datos'),
                  for (final s in sistemas)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${s['nombre']}'),
                      subtitle: Text('${etiquetaDe('${s['tipo']}')} · ${etiquetaDe('${s['estado']}')}'),
                      trailing: Text(s['superficie_ha'] == null
                          ? 'sin datos'
                          : '${valorONo(s['superficie_ha'] as num?, unidad: 'ha')} (${s['naturaleza']})'),
                    ),
                ],
              ),
              Seccion(
                titulo: 'Lluvia del periodo: ${valorONo(lluvia['total_mm'] as num?, unidad: 'mm')}',
                icono: Icons.thunderstorm,
                color: ColoresArea.agroecologia,
                hijos: [
                  ColumnasTiempo(datos: _serie(lluvia['serie']), color: ColoresArea.agroecologia, unidad: 'mm'),
                  Text('1 mm sobre 1 m² = 1 L. Volumen potencial ≠ escorrentía ≠ captado ≠ disponible.',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              Seccion(
                titulo: 'Leche: producida ${valorONo(leche['total_litros'] as num?, unidad: 'L')} · entregada ${valorONo(leche['entregado_litros'] as num?, unidad: 'L')}',
                icono: Icons.local_drink,
                color: ColoresArea.ganaderia,
                hijos: [
                  ColumnasTiempo(datos: _serie(leche['serie']), color: ColoresArea.ganaderia, unidad: 'L'),
                  Text('Pagado en el periodo: ${valorONo(leche['pagado_cop'] as num?, unidad: 'COP')}. Entrega ≠ pago.',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              Seccion(
                titulo: 'Economía del periodo',
                icono: Icons.payments,
                hijos: [
                  BarrasHorizontales(datos: economia, color: ColoresArea.general, unidad: 'COP'),
                  Text(
                    'Costo ≠ gasto ≠ ingreso ≠ pago. Costo por litro (conceptual): '
                    '${costos == 0 || leche['total_litros'] == null ? 'no calculable (faltan costos atribuidos o litros)' : '${(costos / (leche['total_litros'] as num)).toStringAsFixed(0)} COP/L como referencia: la atribución de costos (34.4) no está definida'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              Seccion(
                titulo: 'Pastoreo: aforos recientes',
                icono: Icons.science,
                color: ColoresArea.agroecologia,
                hijos: [
                  if (aforos.isEmpty) const Text('sin datos'),
                  for (final a in aforos)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${a['unidad'] ?? 'unidad'} · ${fechaCorta(a['fecha'], hora: false)}'),
                      subtitle: Text('${a['puntos']} punto(s) · agua ${valorONo(a['agua_pct'] as num?, unidad: '%', faltante: 'no calculable')} · '
                          '${valorONo(a['ms_kg_ha'] as num?, unidad: 'kg MS/ha', faltante: 'kg MS/ha no calculable')}'),
                      trailing: Text(valorONo(a['ms_pct'] as num?, unidad: '% MS', faltante: 'no calculable')),
                    ),
                ],
              ),
              Seccion(
                titulo: 'Operación: actividades por estado',
                icono: Icons.task_alt,
                hijos: [
                  BarrasHorizontales(
                    datos: _pares(actividades['por_estado']),
                    color: ColoresArea.general,
                    alTocar: (_) => context.push('/e/actividades'),
                  ),
                  Text('Vencidas: ${actividades['vencidas'] ?? 0} · Por verificar: ${actividades['por_verificar'] ?? 0}'),
                ],
              ),
              Seccion(
                titulo: 'Monitoreo: alertas abiertas por tipo',
                icono: Icons.warning_amber,
                hijos: [
                  BarrasHorizontales(
                      datos: _pares(alertas['por_tipo']), color: ColoresArea.general, alTocar: (_) => context.push('/e/alertas')),
                ],
              ),
              Seccion(
                titulo: 'Decisiones por estado',
                icono: Icons.gavel,
                hijos: [
                  BarrasHorizontales(
                      datos: _pares(d['decisiones_por_estado']),
                      color: ColoresArea.general,
                      alTocar: (_) => context.push('/e/decisiones')),
                ],
              ),
              Seccion(
                titulo: 'Infraestructura por estado',
                icono: Icons.home_work,
                color: ColoresArea.infraestructura,
                hijos: [
                  BarrasHorizontales(
                      datos: _pares(d['infraestructura_por_estado']),
                      color: ColoresArea.infraestructura,
                      alTocar: (_) => context.push('/e/infraestructuras')),
                ],
              ),
            ]),
          );
        },
      ),
    );
  }
}
