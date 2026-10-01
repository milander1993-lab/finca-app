import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/finca_actual.dart';
import '../../../core/supabase.dart';
import '../../../core/widgets.dart';
import '../data/lotes_repositorio.dart';

class LotesPantalla extends ConsumerWidget {
  const LotesPantalla({super.key});

  Future<void> _nuevo(BuildContext context, WidgetRef ref) async {
    final c = TextEditingController();
    final nombre = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nuevo lote'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Crear')),
        ],
      ),
    );
    final finca = ref.read(fincaActualProvider);
    if (nombre == null || nombre.trim().isEmpty || finca == null) return;
    try {
      await ref.read(lotesRepoProvider).crear(finca.id, nombre);
      ref.invalidate(lotesProvider);
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lotes = ref.watch(lotesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Lotes')),
      floatingActionButton: FloatingActionButton(onPressed: () => _nuevo(context, ref), child: const Icon(Icons.add)),
      body: lotes.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (lista) => lista.isEmpty
            ? const Vacio('Sin lotes registrados.')
            : ListView(children: [
                for (final l in lista)
                  ListTile(title: Text(l.nombre), subtitle: Text(l.estado), trailing: Text('${l.animales} animal(es)')),
              ]),
      ),
    );
  }
}
