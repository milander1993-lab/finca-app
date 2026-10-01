import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/supabase.dart';
import '../../../core/widgets.dart';
import '../data/animales_repositorio.dart';

/// Lista de animales: sirve igual para 1 o 1000 (búsqueda por número).
class AnimalesPantalla extends ConsumerStatefulWidget {
  const AnimalesPantalla({super.key});
  @override
  ConsumerState<AnimalesPantalla> createState() => _AnimalesPantallaState();
}

class _AnimalesPantallaState extends ConsumerState<AnimalesPantalla> {
  String _filtro = '';

  @override
  Widget build(BuildContext context) {
    final animales = ref.watch(animalesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Animales')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/animales/nuevo'),
        icon: const Icon(Icons.add),
        label: const Text('Animal'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar por número o categoría'),
            onChanged: (v) => setState(() => _filtro = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: animales.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Vacio(mensajeError(e)),
            data: (lista) {
              final vis = lista
                  .where((a) => _filtro.isEmpty || a.numeroInterno.toLowerCase().contains(_filtro) || (a.categoria ?? '').toLowerCase().contains(_filtro))
                  .toList();
              if (vis.isEmpty) return const Vacio('Sin animales registrados.');
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(animalesProvider),
                child: ListView.builder(
                  itemCount: vis.length,
                  itemBuilder: (_, i) {
                    final a = vis[i];
                    return ListTile(
                      title: Text(a.numeroInterno),
                      subtitle: Text([a.categoria ?? 'categoría sin registrar', a.estado ?? ''].where((s) => s.isNotEmpty).join(' · ')),
                      trailing: Text(valorONo(a.pesoUltimo, unidad: 'kg')),
                      onTap: () => context.go('/animales/${a.id}'),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
