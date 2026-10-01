import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/ia/ia.dart';
import '../supabase.dart';
import '../transversal/paneles.dart';
import '../widgets.dart';
import 'catalogo.dart';
import 'definicion.dart';
import 'repo_generico.dart';

/// Lista genérica de un módulo: buscar, filtrar por estado, abrir expediente, crear.
class ListaEntidadPantalla extends ConsumerStatefulWidget {
  const ListaEntidadPantalla({super.key, required this.tabla, this.filtros = const {}});
  final String tabla;
  final Map<String, String> filtros;

  @override
  ConsumerState<ListaEntidadPantalla> createState() => _ListaEntidadPantallaState();
}

class _ListaEntidadPantallaState extends ConsumerState<ListaEntidadPantalla> {
  String _texto = '';
  String? _estado;

  EntidadDef get def => catalogo[widget.tabla]!;

  @override
  Widget build(BuildContext context) {
    final filas = ref.watch(listaProvider(ConsultaLista(widget.tabla, widget.filtros)));
    return Scaffold(
      appBar: AppBar(
        title: Text(def.plural),
        actions: [
          if (def.guiaCodigo != null) GuiaBoton(codigo: def.guiaCodigo!, compacto: true),
          IconButton(
            tooltip: 'Asistente',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => AsistenteIA.abrir(context, titulo: def.plural),
          ),
        ],
      ),
      floatingActionButton: widget.tabla == 'alertas'
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                final q = widget.filtros.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&');
                context.push('/e/${widget.tabla}/nuevo${q.isEmpty ? '' : '?$q'}');
              },
              icon: const Icon(Icons.add),
              label: Text('Registrar'),
            ),
      body: filas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (lista) {
          final estados = def.campoEstado == null
              ? <String>[]
              : (lista.map((f) => '${f[def.campoEstado]}').toSet().toList()..sort());
          final visibles = lista.where((f) {
            if (_estado != null && '${f[def.campoEstado]}' != _estado) return false;
            if (_texto.isEmpty) return true;
            final t = _texto.toLowerCase();
            return def.tituloDe(f).toLowerCase().contains(t) || def.subtituloDe(f).toLowerCase().contains(t);
          }).toList();
          return RefreshIndicator(
            onRefresh: () async => refrescarTodo(ref),
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
              if (def.descripcion.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(def.descripcion, style: Theme.of(context).textTheme.bodySmall),
                ),
              TextField(
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar'),
                onChanged: (v) => setState(() => _texto = v.trim()),
              ),
              if (estados.length > 1)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(children: [
                    ChoiceChip(
                      label: Text('Todos (${lista.length})'),
                      selected: _estado == null,
                      onSelected: (_) => setState(() => _estado = null),
                    ),
                    for (final e in estados)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: ChoiceChip(
                          label: Text('${etiquetaDe(e)} (${lista.where((f) => '${f[def.campoEstado]}' == e).length})'),
                          selected: _estado == e,
                          onSelected: (_) => setState(() => _estado = e),
                        ),
                      ),
                  ]),
                ),
              if (visibles.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 40),
                  child: Vacio(lista.isEmpty
                      ? 'Aún no hay ${def.plural.toLowerCase()}. Toque "Registrar" para agregar el primero.'
                      : 'Ningún registro coincide con el filtro.'),
                ),
              for (final f in visibles)
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: def.color.withAlpha(38),
                      child: Icon(def.icono, color: def.color),
                    ),
                    title: Text(def.tituloDe(f), maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [
                        def.subtituloDe(f),
                        if (f['naturaleza'] != null) 'naturaleza: ${f['naturaleza']}',
                        fechaCorta(f['fecha_hecho'] ?? f['fecha_programada'] ?? f['created_at']),
                      ].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/e/${widget.tabla}/${f['id']}'),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}
