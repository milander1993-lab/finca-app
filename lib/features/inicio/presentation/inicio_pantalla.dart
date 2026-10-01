import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tema.dart';
import '../../../core/finca_actual.dart';
import '../../../core/supabase.dart';
import '../../../core/widgets.dart';
import '../../respaldo/respaldo.dart';

/// Menú principal por módulos (sin formularios gigantes).
class InicioPantalla extends ConsumerWidget {
  const InicioPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fincas = ref.watch(fincasProvider);
    final finca = ref.watch(fincaActualProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(finca?.nombre ?? 'Finca'),
        actions: [
          if (finca != null)
            IconButton(
              tooltip: 'Descargar respaldo',
              icon: const Icon(Icons.backup),
              onPressed: () => descargarRespaldo(context, ref),
            ),
          IconButton(
            tooltip: 'Salir',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(supabaseProvider).auth.signOut(),
          ),
        ],
      ),
      body: fincas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (lista) => lista.isEmpty
            ? const _CrearFinca()
            : GridView.extent(
                maxCrossAxisExtent: 220,
                padding: const EdgeInsets.all(16),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                children: [
                  _Modulo('Animales', Icons.pets, ColoresArea.ganaderia, () => context.go('/animales')),
                  _Modulo('Lotes', Icons.groups, ColoresArea.ganaderia, () => context.go('/lotes')),
                  _Modulo('Potreros y aforo', Icons.grass, ColoresArea.agroecologia, () => context.go('/potreros')),
                  _Modulo('QR', Icons.qr_code_scanner, ColoresArea.ganaderia, () => context.go('/qr')),
                ],
              ),
      ),
    );
  }
}

class _Modulo extends StatelessWidget {
  const _Modulo(this.titulo, this.icono, this.color, this.alTocar);
  final String titulo;
  final IconData icono;
  final Color color;
  final VoidCallback alTocar;
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: alTocar,
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icono, size: 40, color: color),
            const SizedBox(height: 8),
            Text(titulo, textAlign: TextAlign.center),
          ]),
        ),
      );
}

/// Primera vez: el usuario crea su finca y queda como miembro (RPC crear_finca_inicial).
class _CrearFinca extends ConsumerStatefulWidget {
  const _CrearFinca();
  @override
  ConsumerState<_CrearFinca> createState() => _CrearFincaState();
}

class _CrearFincaState extends ConsumerState<_CrearFinca> {
  final _nombre = TextEditingController();
  bool _ocupado = false;

  Future<void> _crear() async {
    if (_nombre.text.trim().isEmpty) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(supabaseProvider).rpc('crear_finca_inicial', params: {'p_nombre': _nombre.text.trim()});
      ref.invalidate(fincasProvider);
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('Aún no tiene una finca registrada. Escriba su nombre para crearla.'),
              const SizedBox(height: 12),
              TextField(controller: _nombre, decoration: const InputDecoration(labelText: 'Nombre de la finca')),
              const SizedBox(height: 12),
              FilledButton(onPressed: _ocupado ? null : _crear, child: const Text('Crear finca')),
            ]),
          ),
        ),
      );
}
