import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/finca_actual.dart';
import '../../../core/supabase.dart';
import '../../../core/transversal/paneles.dart';
import '../../../core/widgets.dart';
import '../data/pasturas_repositorio.dart';
import '../domain/pasturas.dart';

/// Aforo con varios puntos de corte. %MS = MS ÷ MF × 100 ; %agua = 100 − %MS.
/// La materia seca se anota después del secado; mientras falte, el punto queda pendiente.
class AforoPantalla extends ConsumerWidget {
  const AforoPantalla({super.key, required this.aforoId});
  final String aforoId;

  void _refrescar(WidgetRef ref) {
    ref.invalidate(aforoProvider(aforoId));
    ref.invalidate(muestrasProvider(aforoId));
    ref.invalidate(aforosProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resumen = ref.watch(aforoProvider(aforoId));
    final muestras = ref.watch(muestrasProvider(aforoId));
    final lista = muestras.valueOrNull ?? const <MuestraAforo>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Aforo'), actions: const [GuiaBoton(codigo: 'aforo_materia_seca', compacto: true)]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _nuevoPunto(context, ref, lista.isEmpty ? 1 : lista.map((m) => m.punto).reduce((a, b) => a > b ? a : b) + 1),
        icon: const Icon(Icons.add),
        label: const Text('Punto de corte'),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        resumen.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(mensajeError(e)),
          data: (r) => Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text('Resumen', style: Theme.of(context).textTheme.titleMedium)),
                  EtiquetaNaturaleza(r.naturaleza),
                ]),
                Text('Puntos: ${r.nPuntos ?? 0} (con materia seca: ${r.nPuntosConMs ?? 0})'),
                Text('Materia seca: ${valorONo(r.msPct, unidad: '%', faltante: 'no calculable')}'),
                Text('Agua: ${valorONo(r.aguaPct, unidad: '%', faltante: 'no calculable')}'),
                Text('Rango entre puntos: ${r.msPctMin == null ? 'no calculable' : '${r.msPctMin}% a ${r.msPctMax}%'}'),
                Text('MS por m²: ${valorONo(r.msGM2, unidad: 'g', faltante: 'no calculable')}'),
                Text('MS por hectárea: ${valorONo(r.msKgHa, unidad: 'kg', faltante: 'no calculable')}'),
                if (r.advertencia != null)
                  Padding(padding: const EdgeInsets.only(top: 8), child: Text(r.advertencia!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (lista.isEmpty) const Vacio('Sin puntos. Corte el área de cada punto y registre su peso fresco.'),
        for (final m in lista)
          ListTile(
            title: Text('Punto ${m.punto}${m.areaM2 == null ? '' : ' · ${m.areaM2} m²'}'),
            subtitle: Text('Fresco: ${valorONo(m.mfG, unidad: 'g')} · Seco: ${valorONo(m.msG, unidad: 'g', faltante: 'pendiente de secado')}'
                '${m.msPct == null ? '' : ' · MS ${m.msPct!.toStringAsFixed(2)}% · agua ${m.aguaPct!.toStringAsFixed(2)}%'}'),
            trailing: m.msG == null && m.mfG != null
                ? TextButton(onPressed: () => _anotarSeco(context, ref, m), child: const Text('Anotar seco'))
                : null,
          ),
      ]),
    );
  }

  Future<void> _nuevoPunto(BuildContext context, WidgetRef ref, int punto) async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    final area = TextEditingController();
    final mf = TextEditingController();
    final ms = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Punto $punto'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: area, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Área cortada (m²)')),
          const SizedBox(height: 8),
          TextField(controller: mf, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Peso fresco (g) *')),
          const SizedBox(height: 8),
          TextField(controller: ms, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'Peso seco (g) — si ya se secó')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar')),
        ],
      ),
    );
    if (ok != true) return;
    num? n(TextEditingController c) => num.tryParse(c.text.replaceAll(',', '.'));
    if (n(mf) == null) {
      if (context.mounted) mostrarMensaje(context, 'Falta el peso fresco: no se guardó.');
      return;
    }
    try {
      await ref.read(pasturasRepoProvider).agregarMuestra(fincaId: finca.id, aforoId: aforoId, punto: punto, areaM2: n(area), mfG: n(mf), msG: n(ms));
      _refrescar(ref);
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  Future<void> _anotarSeco(BuildContext context, WidgetRef ref, MuestraAforo m) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Peso seco del punto ${m.punto}'),
        content: TextField(controller: c, autofocus: true, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: const InputDecoration(labelText: 'g')),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Guardar'))],
      ),
    );
    final v = num.tryParse(c.text.replaceAll(',', '.'));
    if (ok != true || v == null) return;
    try {
      await ref.read(pasturasRepoProvider).registrarMateriaSeca(m.id, v);
      _refrescar(ref);
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }
}
