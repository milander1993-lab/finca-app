import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/finca_actual.dart';
import '../../../core/supabase.dart';
import '../../../core/widgets.dart';
import '../data/animales_repositorio.dart';

/// Alta de animal: solo lo necesario. Categoría y sexo son texto libre con
/// sugerencias (D-013); lo que no exista se escribe a mano.
class AnimalFormPantalla extends ConsumerStatefulWidget {
  const AnimalFormPantalla({super.key});
  @override
  ConsumerState<AnimalFormPantalla> createState() => _AnimalFormPantallaState();
}

class _AnimalFormPantallaState extends ConsumerState<AnimalFormPantalla> {
  final _form = GlobalKey<FormState>();
  final _numero = TextEditingController();
  final _categoria = TextEditingController();
  final _sexo = TextEditingController();
  bool _ocupado = false;

  static const _sugerenciasCategoria = ['ternero', 'ternera', 'levante', 'novilla', 'vaca', 'toro'];

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    setState(() => _ocupado = true);
    try {
      await ref.read(animalesRepoProvider).crear(
            fincaId: finca.id,
            numeroInterno: _numero.text,
            categoria: _categoria.text,
            sexo: _sexo.text,
          );
      ref.invalidate(animalesProvider);
      if (mounted) context.go('/animales');
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Nuevo animal')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextFormField(
              controller: _numero,
              decoration: const InputDecoration(labelText: 'Número interno *'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              optionsBuilder: (t) => _sugerenciasCategoria.where((s) => s.contains(t.text.toLowerCase())),
              onSelected: (s) => _categoria.text = s,
              fieldViewBuilder: (_, c, f, __) {
                c.addListener(() => _categoria.text = c.text);
                return TextField(controller: c, focusNode: f, decoration: const InputDecoration(labelText: 'Categoría (escriba o elija)'));
              },
            ),
            const SizedBox(height: 12),
            TextField(controller: _sexo, decoration: const InputDecoration(labelText: 'Sexo (opcional)')),
            const SizedBox(height: 20),
            FilledButton(onPressed: _ocupado ? null : _guardar, child: const Text('Guardar')),
          ]),
        ),
      );
}
