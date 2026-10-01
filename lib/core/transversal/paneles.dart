import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/guias/guias.dart';
import '../../features/ia/ia.dart';
import '../entidades/catalogo.dart';
import '../entidades/definicion.dart';
import '../entidades/repo_generico.dart';
import '../finca_actual.dart';
import '../supabase.dart';
import '../widgets.dart';

/// Botón de la regla de oro: abre la guía de cómo obtener el dato correctamente.
class GuiaBoton extends ConsumerWidget {
  const GuiaBoton({super.key, required this.codigo, this.compacto = false});
  final String codigo;
  final bool compacto;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void abrir() => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.8,
            builder: (context, scroll) => _HojaGuia(codigo: codigo, scroll: scroll),
          ),
        );
    if (compacto) {
      return IconButton(tooltip: 'Guía: cómo obtener este dato', icon: const Icon(Icons.menu_book), onPressed: abrir);
    }
    return OutlinedButton.icon(
      onPressed: abrir,
      icon: const Icon(Icons.menu_book),
      label: const Text('Guía: cómo obtener este dato correctamente'),
    );
  }
}

class _HojaGuia extends ConsumerWidget {
  const _HojaGuia({required this.codigo, required this.scroll});
  final String codigo;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(guiaPorCodigoProvider(codigo));
    return g.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Vacio(mensajeError(e)),
      data: (guia) {
        if (guia == null || guia.vigente == null) {
          return ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
            const Text('Esta medición aún no tiene guía en su finca.'),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: () async {
                final finca = ref.read(fincaActualProvider);
                if (finca == null) return;
                try {
                  await ref.read(supabaseProvider).rpc('crear_guias_base', params: {'p_finca': finca.id});
                  ref.invalidate(guiasProvider);
                } catch (e) {
                  if (context.mounted) mostrarMensaje(context, mensajeError(e));
                }
              },
              icon: const Icon(Icons.library_add),
              label: const Text('Crear las guías base de la arquitectura'),
            ),
          ]);
        }
        return ListView(controller: scroll, padding: const EdgeInsets.all(16), children: [
          Text('${guia.guia['titulo']}', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ContenidoGuia(version: guia.vigente!),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                context.push('/guias/${guia.guia['id']}');
              },
              icon: const Icon(Icons.open_in_new),
              label: const Text('Abrir guía completa'),
            ),
            OutlinedButton.icon(
              onPressed: () => AsistenteIA.abrir(context,
                  funcion: 'explicar_guia', tabla: 'guias', id: '${guia.guia['id']}', titulo: '${guia.guia['titulo']}'),
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Pedir explicación a la IA'),
            ),
          ]),
        ]);
      },
    );
  }
}

/// Registros de otra tabla vinculados a este objeto (observaciones, evidencias,
/// actividades, alertas). Permite agregar uno ya vinculado.
class PanelVinculados extends ConsumerWidget {
  const PanelVinculados({
    super.key,
    required this.tablaDestino,
    required this.objetoTipo,
    required this.objetoId,
    this.titulo,
    this.permitirAgregar = true,
  });
  final String tablaDestino;
  final String objetoTipo;
  final String objetoId;
  final String? titulo;
  final bool permitirAgregar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final def = catalogo[tablaDestino]!;
    final filas = ref.watch(vinculadosProvider(ClaveVinculo(tablaDestino, objetoTipo, objetoId)));
    return Seccion(
      titulo: titulo ?? def.plural,
      icono: def.icono,
      color: def.color,
      accion: permitirAgregar
          ? IconButton(
              tooltip: 'Agregar ${def.singular.toLowerCase()}',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => context.push(
                  '/e/$tablaDestino/nuevo?objeto_tipo=${Uri.encodeComponent(objetoTipo)}&objeto_id=$objetoId'),
            )
          : null,
      hijos: [
        filas.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(mensajeError(e)),
          data: (lista) => lista.isEmpty
              ? Text('Sin ${def.plural.toLowerCase()} vinculadas.', style: Theme.of(context).textTheme.bodySmall)
              : Column(children: [
                  for (final f in lista)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(def.icono, size: 20, color: def.color),
                      title: Text(def.tituloDe(f), maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: Text([
                        if (def.campoEstado != null) etiquetaDe('${f[def.campoEstado]}'),
                        fechaCorta(f['fecha_programada'] ?? f['fecha_hecho'] ?? f['created_at']),
                      ].join(' · ')),
                      onTap: () => context.push('/e/$tablaDestino/${f['id']}'),
                    ),
                ]),
        ),
      ],
    );
  }
}

/// Registros hijos por clave foránea (p. ej. resultados de una muestra de suelo).
class PanelRelacion extends ConsumerWidget {
  const PanelRelacion({super.key, required this.relacion, required this.padreId});
  final RelacionDef relacion;
  final String padreId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final def = catalogo[relacion.tabla]!;
    final filas = ref.watch(listaProvider(ConsultaLista(relacion.tabla, {relacion.campoFk: padreId})));
    return Seccion(
      titulo: relacion.etiqueta,
      icono: def.icono,
      color: def.color,
      accion: relacion.tabla == 'actividades'
          ? null
          : IconButton(
              tooltip: 'Agregar',
              icon: const Icon(Icons.add_circle_outline),
              onPressed: () => context.push('/e/${relacion.tabla}/nuevo?${relacion.campoFk}=$padreId'),
            ),
      hijos: [
        filas.when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Text(mensajeError(e)),
          data: (lista) => lista.isEmpty
              ? Text('Sin registros.', style: Theme.of(context).textTheme.bodySmall)
              : Column(children: [
                  for (final f in lista)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(def.tituloDe(f)),
                      subtitle: Text(def.subtituloDe(f)),
                      onTap: () => context.push('/e/${relacion.tabla}/${f['id']}'),
                    ),
                ]),
        ),
      ],
    );
  }
}

/// Historial de auditoría de un registro: quién cambió qué, cuándo (append-only).
class PanelAuditoria extends ConsumerWidget {
  const PanelAuditoria({super.key, required this.tabla, required this.id});
  final String tabla;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.manage_history),
        title: const Text('Historial y trazabilidad'),
        subtitle: const Text('Cada cambio queda registrado; nada se borra'),
        children: [
          Consumer(builder: (context, ref, _) {
            final a = ref.watch(auditoriaProvider(ClaveRegistro(tabla, id)));
            return a.when(
              loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
              error: (e, _) => Padding(padding: const EdgeInsets.all(12), child: Text(mensajeError(e))),
              data: (lista) => Column(children: [
                if (lista.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Sin cambios registrados.')),
                for (final f in lista)
                  ListTile(
                    dense: true,
                    leading: Icon(f['accion'] == 'crear'
                        ? Icons.add
                        : f['accion'] == 'anular'
                            ? Icons.block
                            : Icons.edit),
                    title: Text('${etiquetaDe('${f['accion']}')} · ${fechaCorta(f['created_at'])}'),
                    subtitle: Text(_cambios(f)),
                  ),
              ]),
            );
          }),
        ],
      ),
    );
  }

  String _cambios(Map<String, dynamic> f) {
    final antes = f['estado_anterior'];
    final despues = f['estado_nuevo'];
    if (antes is! Map || despues is! Map) return f['motivo'] == null ? '' : 'Motivo: ${f['motivo']}';
    const ignorar = {'updated_at', 'updated_by', 'version', 'sincronizada_en'};
    final partes = <String>[];
    for (final k in despues.keys) {
      if (ignorar.contains(k)) continue;
      if ('${antes[k]}' != '${despues[k]}') {
        partes.add('$k: ${antes[k] ?? 'sin datos'} → ${despues[k] ?? 'sin datos'}');
      }
    }
    return partes.isEmpty ? '' : partes.join('\n');
  }
}

/// Revisión determinística (sin IA) de lo que le falta a un registro.
List<String> camposFaltantes(EntidadDef def, Map<String, dynamic> fila) => [
      for (final c in def.campos)
        if (c.enFormulario && !c.soloLectura && (fila[c.clave] == null || '${fila[c.clave]}'.trim().isEmpty))
          c.etiqueta + (c.obligatorio ? ' (obligatorio)' : ''),
    ];
