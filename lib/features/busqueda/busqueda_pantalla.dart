import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/entidades/catalogo.dart';
import '../../core/entidades/definicion.dart';
import '../../core/finca_actual.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';

/// Búsqueda (§47): localiza sobre la información existente; el módulo contextualiza.
/// Nunca inventa resultados.
class BusquedaPantalla extends ConsumerStatefulWidget {
  const BusquedaPantalla({super.key});
  @override
  ConsumerState<BusquedaPantalla> createState() => _BusquedaPantallaState();
}

class _BusquedaPantallaState extends ConsumerState<BusquedaPantalla> {
  Timer? _espera;
  List<Map<String, dynamic>> _resultados = const [];
  String _texto = '';
  bool _buscando = false;

  @override
  void dispose() {
    _espera?.cancel();
    super.dispose();
  }

  void _cambio(String t) {
    _espera?.cancel();
    _espera = Timer(const Duration(milliseconds: 350), () => _buscar(t));
  }

  Future<void> _buscar(String t) async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    setState(() {
      _texto = t.trim();
      _buscando = true;
    });
    try {
      final r = await ref.read(supabaseProvider).rpc('buscar_finca', params: {'p_finca': finca.id, 'p_texto': t.trim()});
      if (mounted) setState(() => _resultados = List<Map<String, dynamic>>.from((r as List).map((e) => Map<String, dynamic>.from(e as Map))));
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Buscar animal, lote, potrero, actividad, decisión…',
            border: InputBorder.none,
          ),
          onChanged: _cambio,
          onSubmitted: _buscar,
        ),
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        if (_buscando) const LinearProgressIndicator(),
        if (_texto.isEmpty)
          const Vacio('Escriba para buscar en toda la finca.', icono: Icons.search)
        else if (!_buscando && _resultados.isEmpty)
          Vacio('Sin resultados para "$_texto".'),
        for (final r in _resultados)
          Card(
            child: ListTile(
              leading: Icon(catalogo[r['tabla']]?.icono ?? _icono('${r['tabla']}')),
              title: Text('${r['titulo']}'),
              subtitle: Text('${catalogo[r['tabla']]?.singular ?? etiquetaDe('${r['tabla']}')} · ${etiquetaDe('${r['detalle']}')}'),
              onTap: () => context.push(rutaObjeto('${r['tabla']}', '${r['id']}')),
            ),
          ),
      ]),
    );
  }

  IconData _icono(String tabla) => switch (tabla) {
        'animales' => Icons.pets,
        'lotes_ganaderos' => Icons.groups,
        'unidades_espaciales' => Icons.grass,
        'guias' => Icons.menu_book,
        _ => Icons.description,
      };
}
