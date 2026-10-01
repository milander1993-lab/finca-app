import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/entidades/definicion.dart';
import '../../core/finca_actual.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';

final agendaProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const [];
  final r = await ref
      .watch(supabaseProvider)
      .from('v_agenda')
      .select()
      .eq('finca_id', finca.id)
      .order('fecha', ascending: true)
      .limit(500);
  return List<Map<String, dynamic>>.from(r);
});

/// Agenda (§28): vista temporal de actividades y alertas existentes.
/// Alerta ≠ recordatorio ≠ tarea ≠ actividad ≠ seguimiento ≠ decisión.
class AgendaPantalla extends ConsumerStatefulWidget {
  const AgendaPantalla({super.key});
  @override
  ConsumerState<AgendaPantalla> createState() => _AgendaPantallaState();
}

class _AgendaPantallaState extends ConsumerState<AgendaPantalla> {
  String _vista = 'todo';

  String _grupo(Map<String, dynamic> f) {
    if (f['clase'] == 'alerta') return 'Alertas por revisar';
    if (f['estado'] == 'requiere_verificacion') return 'Por verificar';
    if (f['vencida'] == true) return 'Vencidas';
    if (f['sin_fecha'] == true) return 'Pendientes sin fecha';
    final d = DateTime.tryParse('${f['fecha']}')?.toLocal();
    if (d == null) return 'Pendientes sin fecha';
    final hoy = DateTime.now();
    final h = DateTime(hoy.year, hoy.month, hoy.day);
    final dia = DateTime(d.year, d.month, d.day);
    final dif = dia.difference(h).inDays;
    if (dif <= 0) return 'Hoy';
    if (dif == 1) return 'Mañana';
    if (dif <= 7) return 'Próximos 7 días';
    return 'Más adelante';
  }

  @override
  Widget build(BuildContext context) {
    final a = ref.watch(agendaProvider);
    const orden = ['Alertas por revisar', 'Vencidas', 'Hoy', 'Por verificar', 'Mañana', 'Próximos 7 días', 'Más adelante', 'Pendientes sin fecha'];
    return Scaffold(
      appBar: AppBar(title: const Text('Agenda')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/e/actividades/nuevo'),
        icon: const Icon(Icons.add_task),
        label: const Text('Programar actividad'),
      ),
      body: a.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (lista) {
          final filtrada = lista.where((f) => _vista == 'todo' || f['clase'] == _vista).toList();
          final grupos = <String, List<Map<String, dynamic>>>{};
          for (final f in filtrada) {
            grupos.putIfAbsent(_grupo(f), () => []).add(f);
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(agendaProvider),
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'todo', label: Text('Todo')),
                  ButtonSegment(value: 'actividad', label: Text('Actividades')),
                  ButtonSegment(value: 'alerta', label: Text('Alertas')),
                ],
                selected: {_vista},
                onSelectionChanged: (s) => setState(() => _vista = s.first),
              ),
              const SizedBox(height: 8),
              const Text(
                'Muchas tareas se crean solas: salida de pastoreo al límite de 48 h, completar aforos, revisar observaciones '
                'sanitarias, diagnóstico de gestación tras un servicio, reparaciones, envío de muestras de suelo y las '
                'actividades de las decisiones aprobadas.',
              ),
              if (filtrada.isEmpty) const Padding(padding: EdgeInsets.only(top: 40), child: Vacio('Nada pendiente.')),
              for (final g in orden)
                if (grupos[g] != null) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                    child: Text('$g (${grupos[g]!.length})', style: Theme.of(context).textTheme.titleMedium),
                  ),
                  for (final f in grupos[g]!)
                    Card(
                      child: ListTile(
                        leading: Icon(f['clase'] == 'alerta'
                            ? Icons.warning_amber
                            : f['vencida'] == true
                                ? Icons.alarm
                                : Icons.task_alt),
                        title: Text('${f['titulo']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          etiquetaDe('${f['estado']}'),
                          if (f['proceso'] != null) etiquetaDe('${f['proceso']}'),
                          if (f['sin_fecha'] != true) fechaCorta(f['fecha']),
                          if (f['responsable'] != null) 'Resp.: ${f['responsable']}',
                        ].join(' · ')),
                        onTap: () => context.push(f['clase'] == 'alerta' ? '/e/alertas/${f['id']}' : '/e/actividades/${f['id']}'),
                      ),
                    ),
                ],
            ]),
          );
        },
      ),
    );
  }
}
