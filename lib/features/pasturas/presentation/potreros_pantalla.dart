import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/tema.dart';
import '../../../core/finca_actual.dart';
import '../../../core/supabase.dart';
import '../../../core/transversal/paneles.dart';
import '../../../core/widgets.dart';
import '../../lotes/data/lotes_repositorio.dart';
import '../data/pasturas_repositorio.dart';
import '../domain/pasturas.dart';

final _fmt = DateFormat('d MMM HH:mm', 'es');

/// Potreros (máx. 6, lo controla el servidor) con sus divisiones A1, A2…,
/// ocupación actual, alerta de más de 2 días y acceso al aforo.
class PotrerosPantalla extends ConsumerWidget {
  const PotrerosPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unidades = ref.watch(unidadesProvider);
    final ocupaciones = ref.watch(ocupacionesProvider).valueOrNull ?? const <OcupacionVista>[];
    final abiertas = {for (final o in ocupaciones.where((o) => o.abierta)) o.unidadId: o};
    final alertas = ocupaciones.where((o) => o.abierta && o.excede).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Potreros y aforo'), actions: const [
        GuiaBoton(codigo: 'ocupacion_pastoreo', compacto: true),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _pedirNombre(context, 'Nuevo potrero', (n) async {
          final f = ref.read(fincaActualProvider)!;
          await ref.read(pasturasRepoProvider).crearPotrero(f.id, n);
        }, ref),
        icon: const Icon(Icons.add),
        label: const Text('Potrero'),
      ),
      body: unidades.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (lista) {
          final potreros = lista.where((u) => u.esPotrero).toList();
          if (potreros.isEmpty) return const Vacio('Sin potreros registrados (máximo 6).');
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(unidadesProvider);
              ref.invalidate(ocupacionesProvider);
            },
            child: ListView(children: [
              for (final a in alertas)
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: ListTile(
                    leading: const Icon(Icons.warning_amber),
                    title: Text('${a.unidadNombre} · ${a.loteNombre}'),
                    subtitle: Text(a.mensaje ?? 'Ocupación superior a 2 días (causa por determinar)'),
                  ),
                ),
              for (final p in potreros)
                ExpansionTile(
                  leading: const Icon(Icons.grass, color: ColoresArea.agroecologia),
                  title: Text(p.nombre),
                  subtitle: Text(p.superficieHa == null ? 'superficie sin datos' : '${p.superficieHa} ha (${p.superficieNaturaleza})'),
                  children: [
                    _FilaUnidad(unidad: p, ocupacion: abiertas[p.id]),
                    for (final d in lista.where((u) => u.parentId == p.id)) _FilaUnidad(unidad: d, ocupacion: abiertas[d.id]),
                    TextButton.icon(
                      icon: const Icon(Icons.call_split),
                      label: const Text('Agregar división (A1, A2…)'),
                      onPressed: () => _pedirNombre(context, 'Nueva división de ${p.nombre}', (n) async {
                        final f = ref.read(fincaActualProvider)!;
                        await ref.read(pasturasRepoProvider).crearDivision(f.id, p.id, n);
                      }, ref),
                    ),
                  ],
                ),
            ]),
          );
        },
      ),
    );
  }
}

Future<void> _pedirNombre(BuildContext context, String titulo, Future<void> Function(String) accion, WidgetRef ref) async {
  final c = TextEditingController();
  final n = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Guardar')),
      ],
    ),
  );
  if (n == null || n.trim().isEmpty) return;
  try {
    await accion(n.trim());
    ref.invalidate(unidadesProvider);
  } catch (e) {
    if (context.mounted) mostrarMensaje(context, mensajeError(e));
  }
}

class _FilaUnidad extends ConsumerWidget {
  const _FilaUnidad({required this.unidad, this.ocupacion});
  final Unidad unidad;
  final OcupacionVista? ocupacion;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final o = ocupacion;
    return ListTile(
      contentPadding: EdgeInsets.only(left: unidad.esPotrero ? 16 : 40, right: 8),
      title: Text(unidad.esPotrero ? '${unidad.nombre} (completo)' : unidad.nombre),
      subtitle: Text(o == null
          ? 'libre'
          : 'ocupado por ${o.loteNombre} desde ${_fmt.format(o.entrada.toLocal())} · ${o.horas.toStringAsFixed(0)} h'),
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _accion(context, ref, v),
        itemBuilder: (_) => [
          if (o == null) const PopupMenuItem(value: 'entrar', child: Text('Iniciar pastoreo')),
          if (o != null) const PopupMenuItem(value: 'salir', child: Text('Terminar pastoreo')),
          const PopupMenuItem(value: 'aforo', child: Text('Nuevo aforo')),
          const PopupMenuItem(value: 'superficie', child: Text('Registrar hectáreas')),
        ],
      ),
    );
  }

  Future<void> _accion(BuildContext context, WidgetRef ref, String accion) async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    final repo = ref.read(pasturasRepoProvider);
    try {
      switch (accion) {
        case 'entrar':
          final lotes = await ref.read(lotesProvider.future);
          if (!context.mounted) return;
          if (lotes.isEmpty) return mostrarMensaje(context, 'Primero cree un lote.');
          final lote = await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(title: const Text('¿Qué lote entra?'), children: [
              for (final l in lotes) SimpleDialogOption(onPressed: () => Navigator.pop(ctx, l.id), child: Text(l.nombre)),
            ]),
          );
          if (lote == null) return;
          await repo.iniciarOcupacion(fincaId: finca.id, unidadId: unidad.id, loteId: lote, entrada: DateTime.now());
        case 'salir':
          await repo.cerrarOcupacion(ocupacion!.id, DateTime.now());
        case 'aforo':
          final naturaleza = await showDialog<String>(
            context: context,
            builder: (ctx) => SimpleDialog(title: const Text('¿Cómo se obtendrá el aforo?'), children: [
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'medido'), child: const Text('Medido (corte y pesaje)')),
              SimpleDialogOption(onPressed: () => Navigator.pop(ctx, 'estimado'), child: const Text('Estimado (visual)')),
            ]),
          );
          if (naturaleza == null) return;
          final id = await repo.crearAforo(fincaId: finca.id, unidadId: unidad.id, fecha: DateTime.now(), naturaleza: naturaleza);
          if (context.mounted) context.go('/aforo/$id');
        case 'superficie':
          final c = TextEditingController();
          String nat = 'estimado';
          final ok = await showDialog<bool>(
            context: context,
            builder: (ctx) => StatefulBuilder(
              builder: (ctx, set) => AlertDialog(
                title: Text('Hectáreas de ${unidad.nombre}'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextField(controller: c, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'ha')),
                  DropdownButtonFormField<String>(
                    value: nat,
                    items: const [
                      DropdownMenuItem(value: 'estimado', child: Text('Estimado')),
                      DropdownMenuItem(value: 'medido', child: Text('Medido (GPS/levantamiento)')),
                    ],
                    onChanged: (v) => set(() => nat = v ?? nat),
                  ),
                ]),
                actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar'))],
              ),
            ),
          );
          final ha = num.tryParse(c.text.replaceAll(',', '.'));
          if (ok == true && ha != null) await repo.registrarSuperficie(unidad.id, ha, nat);
      }
      ref.invalidate(unidadesProvider);
      ref.invalidate(ocupacionesProvider);
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }
}
