import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/tema.dart';
import '../../core/finca_actual.dart';
import '../../core/supabase.dart';
import '../../core/transversal/paneles.dart';
import '../../core/widgets.dart';
import '../lotes/data/lotes_repositorio.dart';

final indicadoresProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final r = await ref.watch(supabaseProvider).from('indicadores_def').select().order('nivel').order('codigo');
  return List<Map<String, dynamic>>.from(r);
});

final calculosProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const [];
  final r = await ref
      .watch(supabaseProvider)
      .from('calculos')
      .select()
      .eq('finca_id', finca.id)
      .eq('is_deleted', false)
      .order('created_at', ascending: false)
      .limit(50);
  return List<Map<String, dynamic>>.from(r);
});

final descansoProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const [];
  final r = await ref
      .watch(supabaseProvider)
      .from('v_descanso_unidades')
      .select()
      .eq('finca_id', finca.id)
      .order('entrada_en', ascending: false)
      .limit(30);
  return List<Map<String, dynamic>>.from(r);
});

/// Monitoreo e indicadores (nivel 5): solo fórmulas acordadas, con su propósito,
/// fuente y limitaciones; cada cálculo guarda entradas, criterio y versión.
class MonitoreoPantalla extends ConsumerWidget {
  const MonitoreoPantalla({super.key});

  Future<void> _calcularDemanda(BuildContext context, WidgetRef ref) async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    final lotes = await ref.read(lotesProvider.future);
    if (!context.mounted) return;
    if (lotes.isEmpty) {
      mostrarMensaje(context, 'Primero cree un lote con animales.');
      return;
    }
    final lote = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Demanda de materia seca: elija el lote'),
        children: [
          for (final l in lotes)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, l.id), child: Text('${l.nombre} (${l.animales} animales)')),
        ],
      ),
    );
    if (lote == null) return;
    try {
      final r = await ref.read(supabaseProvider).rpc('calcular_demanda_ms_lote',
          params: {'p_finca': finca.id, 'p_lote': lote, 'p_fecha': DateTime.now().toUtc().toIso8601String()});
      ref.invalidate(calculosProvider);
      if (!context.mounted) return;
      final m = Map<String, dynamic>.from(r as Map);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(m['resultado'] == 'calculado'
              ? 'Demanda: ${valorONo(m['valor'] as num?, unidad: '${m['unidad']}')}'
              : 'No calculable'),
          content: SingleChildScrollView(child: _Traza(calculo: m)),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))],
        ),
      );
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ind = ref.watch(indicadoresProvider);
    final calc = ref.watch(calculosProvider);
    final desc = ref.watch(descansoProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Indicadores y cálculos')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        const Text('Flujo: datos → validación → cálculos → indicadores → comparación con criterios → señales → análisis. '
            'Si falta un dato indispensable el resultado es NO CALCULABLE (nunca 0).'),
        Seccion(
          titulo: 'Calcular',
          icono: Icons.functions,
          hijos: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => _calcularDemanda(context, ref),
                icon: const Icon(Icons.calculate),
                label: const Text('Demanda de MS de un lote'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.push('/config'),
                icon: const Icon(Icons.tune),
                label: const Text('Criterio de consumo (%)'),
              ),
              const GuiaBoton(codigo: 'demanda_ms'),
            ]),
          ],
        ),
        Seccion(
          titulo: 'Cálculos realizados (trazables)',
          icono: Icons.history,
          hijos: [
            calc.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(mensajeError(e)),
              data: (l) => l.isEmpty
                  ? const Text('Aún no hay cálculos guardados.')
                  : Column(children: [
                      for (final c in l)
                        ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          leading: Icon(c['resultado'] == 'calculado' ? Icons.check_circle_outline : Icons.help_outline),
                          title: Text('${c['codigo_calculo']}: ${c['resultado'] == 'calculado' ? valorONo(c['valor'] as num?, unidad: '${c['unidad']}') : 'no calculable'}'),
                          subtitle: Text('${fechaCorta(c['created_at'])} · fórmula v${c['version_formula']}'),
                          children: [_Traza(calculo: c)],
                        ),
                    ]),
            ),
          ],
        ),
        Seccion(
          titulo: 'Descanso de las áreas',
          icono: Icons.bedtime,
          color: ColoresArea.agroecologia,
          hijos: [
            desc.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(mensajeError(e)),
              data: (l) => l.isEmpty
                  ? const Text('sin datos: aún no hay ocupaciones registradas.')
                  : Column(children: [
                      for (final d in l)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${d['unidad_nombre']} · entrada ${fechaCorta(d['entrada_en'])}'),
                          trailing: Text(d['dias_descanso'] == null ? 'no calculable' : '${d['dias_descanso']} días'),
                          subtitle: Text(d['salida_anterior'] == null
                              ? 'Sin salida anterior registrada'
                              : 'Salida anterior ${fechaCorta(d['salida_anterior'])}'),
                        ),
                    ]),
            ),
          ],
        ),
        Seccion(
          titulo: 'Indicadores definidos (solo fórmulas acordadas)',
          icono: Icons.list_alt,
          hijos: [
            ind.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(mensajeError(e)),
              data: (l) => Column(children: [
                for (final i in l)
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    leading: Icon(i['estado'] == 'activo' ? Icons.check : Icons.lightbulb_outline),
                    title: Text('${i['nombre']} (${i['unidad']})'),
                    subtitle: Text('Nivel ${i['nivel']} · ${i['estado']}'),
                    childrenPadding: const EdgeInsets.only(bottom: 8),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Propósito: ${i['proposito']}'),
                      Text('Fórmula: ${i['formula']}'),
                      Text('Datos de origen: ${i['datos_origen']}'),
                      Text('Frecuencia: ${i['frecuencia']}'),
                      Text('Criterio: ${i['criterio']}'),
                      Text('Fuente: ${i['fuente']} · versión ${i['version']}'),
                      Text('Limitaciones: ${i['limitaciones']}'),
                    ],
                  ),
              ]),
            ),
          ],
        ),
      ]),
    );
  }
}

/// Traza de un cálculo (§40, §86): entradas con su naturaleza, fórmula, criterio, versión, faltantes.
class _Traza extends StatelessWidget {
  const _Traza({required this.calculo});
  final Map<String, dynamic> calculo;

  @override
  Widget build(BuildContext context) {
    String bonito(Object? v) {
      if (v == null) return 'ninguno';
      try {
        return const JsonEncoder.withIndent('  ').convert(v is String ? jsonDecode(v) : v);
      } catch (_) {
        return '$v';
      }
    }

    final estilo = Theme.of(context).textTheme.bodySmall;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Fórmula: ${calculo['formula']} (versión ${calculo['version_formula']})'),
      Text('Naturaleza del resultado: ${calculo['naturaleza'] ?? 'calculado'}'),
      if (calculo['incertidumbre'] != null) Text('Incertidumbre: ${calculo['incertidumbre']}'),
      const SizedBox(height: 6),
      const Text('Entradas usadas:'),
      SelectableText(bonito(calculo['entradas']), style: estilo),
      if (calculo['faltantes'] != null) ...[
        const SizedBox(height: 6),
        const Text('Por qué no es calculable:'),
        SelectableText(bonito(calculo['faltantes']), style: estilo),
      ],
    ]);
  }
}
