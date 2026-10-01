import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/finca_actual.dart';
import '../../../core/supabase.dart';
import '../../../core/widgets.dart';
import '../../lotes/data/lotes_repositorio.dart';
import '../data/animales_repositorio.dart';

final _fmt = DateFormat('d MMM y HH:mm', 'es');

/// Expediente del animal: vista sobre los datos integrados (no es una base paralela).
class AnimalDetallePantalla extends ConsumerWidget {
  const AnimalDetallePantalla({super.key, required this.animalId});
  final String animalId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animal = ref.watch(animalProvider(animalId));
    final pesajes = ref.watch(pesajesProvider(animalId));
    final historial = ref.watch(historialLoteProvider(animalId));
    return Scaffold(
      appBar: AppBar(title: Text(animal.valueOrNull?.numeroInterno ?? 'Animal')),
      body: animal.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (a) => ListView(padding: const EdgeInsets.all(16), children: [
          Text('Categoría: ${a.categoria ?? 'sin registrar'}'),
          Text('Sexo: ${a.sexo ?? 'sin registrar'}'),
          Text('Estado: ${a.estado ?? 'sin registrar'}'),
          const Divider(),
          Row(children: [
            Expanded(child: Text('Pesajes', style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(onPressed: () => _registrarPesaje(context, ref), icon: const Icon(Icons.add), label: const Text('Pesaje')),
          ]),
          ...pesajes.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(mensajeError(e))],
            data: (l) => l.isEmpty
                ? [const Text('Sin pesajes (sin datos).')]
                : [
                    for (final p in l)
                      ListTile(
                        dense: true,
                        title: Text('${p.valorKg} kg'),
                        subtitle: Text('${_fmt.format(p.fecha.toLocal())}${p.metodo == null ? '' : ' · ${p.metodo}'}'
                            '${p.estadoCalidad == null || p.estadoCalidad == 'registrado' ? '' : ' · ${p.estadoCalidad}'}'),
                        trailing: EtiquetaNaturaleza(p.naturaleza),
                      ),
                  ],
          ),
          const Divider(),
          Row(children: [
            Expanded(child: Text('Lote (historial)', style: Theme.of(context).textTheme.titleMedium)),
            TextButton.icon(onPressed: () => _moverLote(context, ref), icon: const Icon(Icons.swap_horiz), label: const Text('Mover')),
          ]),
          ...historial.when(
            loading: () => [const LinearProgressIndicator()],
            error: (e, _) => [Text(mensajeError(e))],
            data: (l) => l.isEmpty
                ? [const Text('Sin lote asignado.')]
                : [
                    for (final h in l)
                      ListTile(
                        dense: true,
                        title: Text(h.loteNombre),
                        subtitle: Text('Desde ${_fmt.format(h.desde.toLocal())}'
                            '${h.hasta == null ? ' · actual' : ' hasta ${_fmt.format(h.hasta!.toLocal())} (${h.motivoSalida ?? ''})'}'),
                      ),
                  ],
          ),
        ]),
      ),
    );
  }

  Future<void> _registrarPesaje(BuildContext context, WidgetRef ref) async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    final valor = TextEditingController();
    final metodo = TextEditingController();
    String? naturaleza;
    var fecha = DateTime.now();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Registrar pesaje'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: valor, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Peso (kg) *')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: naturaleza,
                decoration: const InputDecoration(labelText: '¿Cómo se obtuvo? *'),
                items: const [
                  DropdownMenuItem(value: 'medido', child: Text('Medido (báscula)')),
                  DropdownMenuItem(value: 'estimado', child: Text('Estimado (cinta, ojo)')),
                  DropdownMenuItem(value: 'observado', child: Text('Observado')),
                ],
                onChanged: (v) => set(() => naturaleza = v),
              ),
              const SizedBox(height: 8),
              TextField(controller: metodo, decoration: const InputDecoration(labelText: 'Método / instrumento')),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Fecha del pesaje: ${_fmt.format(fecha)}'),
                trailing: const Icon(Icons.edit_calendar),
                onTap: () async {
                  final d = await showDatePicker(context: ctx, initialDate: fecha, firstDate: DateTime(2000), lastDate: DateTime.now());
                  if (d != null) set(() => fecha = DateTime(d.year, d.month, d.day, fecha.hour, fecha.minute));
                },
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final kg = num.tryParse(valor.text.replaceAll(',', '.'));
    if (kg == null || naturaleza == null) {
      if (context.mounted) mostrarMensaje(context, 'Falta el peso o cómo se obtuvo: no se guardó.');
      return;
    }
    try {
      await ref.read(animalesRepoProvider).registrarPesaje(
            fincaId: finca.id, animalId: animalId, fecha: fecha, valorKg: kg, naturaleza: naturaleza!, metodo: metodo.text);
      ref.invalidate(pesajesProvider(animalId));
      ref.invalidate(animalProvider(animalId));
      ref.invalidate(animalesProvider);
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  Future<void> _moverLote(BuildContext context, WidgetRef ref) async {
    final finca = ref.read(fincaActualProvider);
    final lotes = await ref.read(lotesProvider.future);
    if (!context.mounted || finca == null) return;
    if (lotes.isEmpty) {
      mostrarMensaje(context, 'Primero cree un lote.');
      return;
    }
    String? loteId;
    final motivo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('Mover a lote'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              value: loteId,
              decoration: const InputDecoration(labelText: 'Lote destino'),
              items: [for (final l in lotes) DropdownMenuItem(value: l.id, child: Text(l.nombre))],
              onChanged: (v) => set(() => loteId = v),
            ),
            const SizedBox(height: 8),
            TextField(controller: motivo, decoration: const InputDecoration(labelText: 'Motivo *')),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mover')),
          ],
        ),
      ),
    );
    if (ok != true || loteId == null || motivo.text.trim().isEmpty) return;
    try {
      await ref.read(lotesRepoProvider).moverAnimal(
          fincaId: finca.id, animalId: animalId, loteId: loteId!, fecha: DateTime.now(), motivo: motivo.text.trim());
      ref.invalidate(historialLoteProvider(animalId));
      ref.invalidate(lotesProvider);
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }
}
