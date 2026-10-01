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

/// Expediente genérico (§46): identidad → estado → relaciones → historia →
/// actividades → decisiones → evidencias → verificación → análisis.
/// Es una vista sobre la misma información, no una segunda base de datos.
class ExpedienteEntidadPantalla extends ConsumerWidget {
  const ExpedienteEntidadPantalla({super.key, required this.tabla, required this.id});
  final String tabla;
  final String id;

  EntidadDef get def => catalogo[tabla]!;

  Future<void> _cambiarEstado(BuildContext context, WidgetRef ref, Map<String, dynamic> fila, String destino) async {
    final pedir = def.camposPorEstado[destino] ?? const <String>[];
    final cambios = <String, dynamic>{def.campoEstado!: destino};
    const siemprePedir = {'resultado', 'verificacion', 'nota_estado', 'nota', 'nota_revision'};
    for (final clave in pedir) {
      final c = def.campo(clave);
      final actual = fila[clave];
      // Lo que ya está escrito (p. ej. trazabilidad de la decisión) no se vuelve a pedir.
      if (!siemprePedir.contains(clave) && actual != null && '$actual'.trim().isNotEmpty) continue;
      if (c != null && c.tipo == TipoCampo.fechaHora) {
        if (actual != null) continue;
        final d = await showDatePicker(
            context: context, initialDate: DateTime.now(), firstDate: DateTime(1990), lastDate: DateTime(2100));
        if (d == null || !context.mounted) return;
        cambios[clave] = DateTime(d.year, d.month, d.day, 12).toUtc().toIso8601String();
        continue;
      }
      final texto = await pedirTexto(context,
          titulo: '${etiquetaDe(destino)}: ${c?.etiqueta ?? clave}',
          etiqueta: c?.etiqueta ?? clave,
          ayuda: c?.ayuda,
          inicial: actual?.toString() ?? '');
      if (texto == null || !context.mounted) return;
      if (c?.tipo == TipoCampo.decimal) {
        cambios[clave] = double.tryParse(texto.replaceAll(',', '.'));
      } else {
        cambios[clave] = texto;
      }
    }
    try {
      await ref.read(repoProvider).actualizar(tabla, id, cambios);
      refrescarTodo(ref);
      if (context.mounted) mostrarMensaje(context, 'Estado: ${etiquetaDe(destino)}. Lo conectado se actualizó.');
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  Future<void> _anular(BuildContext context, WidgetRef ref) async {
    final motivo = await pedirTexto(context,
        titulo: 'Anular registro', etiqueta: 'Motivo', ayuda: 'Anular no borra: queda en la historia con su motivo.');
    if (motivo == null) return;
    try {
      await ref.read(repoProvider).anular(tabla, id, motivo, conMotivo: def.tieneMotivoAnulacion);
      refrescarTodo(ref);
      if (context.mounted) context.pop();
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  Future<void> _convertirAlerta(BuildContext context, WidgetRef ref, String destino) async {
    final titulo = await pedirTexto(context,
        titulo: 'Convertir en ${etiquetaDe(destino).toLowerCase()}', etiqueta: 'Título', obligatorio: false);
    if (titulo == null) return;
    try {
      final nuevo = await ref.read(repoProvider).rpc('convertir_alerta', {
        'p_alerta': id,
        'p_destino': destino,
        'p_titulo': titulo,
        'p_fecha': null,
      });
      refrescarTodo(ref);
      final tablaDestino = switch (destino) {
        'actividad' => 'actividades',
        'decision' => 'decisiones',
        _ => 'hallazgos',
      };
      if (context.mounted) context.push('/e/$tablaDestino/$nuevo');
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final registro = ref.watch(registroProvider(ClaveRegistro(tabla, id)));
    return Scaffold(
      appBar: AppBar(
        title: Text(def.singular),
        actions: [
          if (def.guiaCodigo != null) GuiaBoton(codigo: def.guiaCodigo!, compacto: true),
          IconButton(
            tooltip: 'Editar',
            icon: const Icon(Icons.edit),
            onPressed: () => context.push('/e/$tabla/$id/editar'),
          ),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'anular') _anular(context, ref);
            },
            itemBuilder: (_) => const [PopupMenuItem(value: 'anular', child: Text('Anular (con motivo)'))],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'ia',
        onPressed: () => AsistenteIA.abrir(context,
            tabla: tabla, id: id, titulo: registro.valueOrNull == null ? def.singular : def.tituloDe(registro.value!)),
        icon: const Icon(Icons.auto_awesome),
        label: const Text('Asistente'),
      ),
      body: registro.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (fila) {
          if (fila == null) return const Vacio('Registro no encontrado o anulado.');
          final estado = def.campoEstado == null || fila[def.campoEstado] == null ? null : '${fila[def.campoEstado]}';
          final siguientes = estado == null ? const <String>[] : (def.transiciones[estado] ?? const <String>[]);
          final faltan = camposFaltantes(def, fila);
          return RefreshIndicator(
            onRefresh: () async => refrescarTodo(ref),
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 96), children: [
              // Identidad y estado
              Row(children: [
                CircleAvatar(
                  backgroundColor: def.color.withAlpha(38),
                  child: Icon(def.icono, color: def.color),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(def.tituloDe(fila), style: Theme.of(context).textTheme.titleLarge)),
              ]),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 4, children: [
                ChipEstado('Nivel ${def.nivel}', icono: Icons.layers),
                if (estado != null) ChipEstado(etiquetaDe(estado), icono: Icons.flag),
                if (fila['naturaleza'] != null) EtiquetaNaturaleza('${fila['naturaleza']}'),
                if (fila['estado_calidad'] != null) ChipEstado('Calidad: ${etiquetaDe('${fila['estado_calidad']}')}', icono: Icons.fact_check),
              ]),
              // Transiciones (la base valida; la interfaz solo ofrece las previstas)
              if (siguientes.isNotEmpty)
                Seccion(
                  titulo: 'Siguiente paso',
                  icono: Icons.alt_route,
                  hijos: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final s in siguientes)
                        OutlinedButton(
                          onPressed: () => _cambiarEstado(context, ref, fila, s),
                          child: Text(etiquetaDe(s)),
                        ),
                    ]),
                  ],
                ),
              if (tabla == 'alertas' && ['generada', 'pendiente', 'revisada', 'en_analisis'].contains(estado))
                Seccion(
                  titulo: 'Tratar la alerta (no demuestra la causa)',
                  icono: Icons.call_split,
                  hijos: [
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      FilledButton.tonal(
                          onPressed: () => _convertirAlerta(context, ref, 'actividad'), child: const Text('Convertir en actividad')),
                      FilledButton.tonal(
                          onPressed: () => _convertirAlerta(context, ref, 'hallazgo'), child: const Text('Analizar (señal)')),
                      FilledButton.tonal(
                          onPressed: () => _convertirAlerta(context, ref, 'decision'), child: const Text('Llevar a decisión')),
                    ]),
                  ],
                ),
              if (tabla == 'recomendaciones' && ['generada', 'revision', 'aceptada', 'modificada'].contains(estado))
                Seccion(
                  titulo: 'Decidir (recomendación ≠ decisión)',
                  icono: Icons.gavel,
                  hijos: [
                    FilledButton.tonal(
                      onPressed: () => context.push(
                          '/e/decisiones/nuevo?recomendacion_id=$id&titulo=${Uri.encodeComponent(def.tituloDe(fila))}'),
                      child: const Text('Crear decisión a partir de esta recomendación'),
                    ),
                  ],
                ),
              if ((tabla == 'actividades' && ['verificada', 'cerrada'].contains(estado)) ||
                  (tabla == 'decisiones' && ['verificada', 'cerrada'].contains(estado)))
                Seccion(
                  titulo: 'Mejora continua',
                  icono: Icons.school,
                  hijos: [
                    FilledButton.tonal(
                      onPressed: () => context.push(
                          '/e/aprendizajes/nuevo?titulo=${Uri.encodeComponent('Aprendizaje: ${def.tituloDe(fila)}')}'),
                      child: const Text('Registrar lo aprendido'),
                    ),
                  ],
                ),
              // Datos
              Seccion(
                titulo: 'Datos',
                icono: Icons.list_alt,
                hijos: [
                  for (final c in def.campos)
                    if (c.tipo != TipoCampo.referencia || fila[c.clave] != null)
                      _FilaDato(campo: c, valor: fila[c.clave]),
                  _FilaDato(campo: const CampoDef('created_at', 'Registrado', tipo: TipoCampo.fechaHora), valor: fila['created_at']),
                  if (fila['sincronizada_en'] != null)
                    _FilaDato(
                        campo: const CampoDef('sincronizada_en', 'Sincronizado', tipo: TipoCampo.fechaHora),
                        valor: fila['sincronizada_en']),
                ],
              ),
              if (fila['objeto_tipo'] != null && fila['objeto_id'] != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.link),
                    title: Text('Ver ${etiquetaDe('${fila['objeto_tipo']}').toLowerCase()} vinculado'),
                    onTap: () => context.push(rutaObjeto('${fila['objeto_tipo']}', '${fila['objeto_id']}')),
                  ),
                ),
              if (faltan.isNotEmpty)
                Seccion(
                  titulo: 'Información faltante (${faltan.length})',
                  icono: Icons.rule,
                  hijos: [Text(faltan.join(' · '), style: Theme.of(context).textTheme.bodySmall)],
                ),
              // Relaciones
              for (final r in def.relaciones) PanelRelacion(relacion: r, padreId: id),
              // Transversales
              if (tabla != 'actividades')
                PanelVinculados(tablaDestino: 'actividades', objetoTipo: tabla, objetoId: id, titulo: 'Actividades y tareas'),
              if (tabla != 'alertas' && tabla != 'actividades')
                PanelVinculados(
                    tablaDestino: 'alertas', objetoTipo: tabla, objetoId: id, titulo: 'Alertas', permitirAgregar: false),
              if (tabla != 'observaciones') PanelVinculados(tablaDestino: 'observaciones', objetoTipo: tabla, objetoId: id),
              if (tabla != 'evidencias') PanelVinculados(tablaDestino: 'evidencias', objetoTipo: tabla, objetoId: id),
              PanelAuditoria(tabla: tabla, id: id),
            ]),
          );
        },
      ),
    );
  }
}

class _FilaDato extends ConsumerWidget {
  const _FilaDato({required this.campo, required this.valor});
  final CampoDef campo;
  final Object? valor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tema = Theme.of(context);
    Widget valorWidget;
    if (campo.tipo == TipoCampo.referencia && valor != null && campo.refTabla != null) {
      final r = ref.watch(registroProvider(ClaveRegistro(campo.refTabla!, '$valor')));
      final texto = r.valueOrNull == null ? '…' : '${r.value![campo.refEtiqueta ?? 'nombre'] ?? '(sin nombre)'}';
      valorWidget = InkWell(
        onTap: () => context.push(rutaObjeto(campo.refTabla, '$valor')),
        child: Text(texto, style: tema.textTheme.bodyMedium?.copyWith(decoration: TextDecoration.underline)),
      );
    } else {
      final t = textoValor(campo, valor);
      valorWidget = Text(
        t + (valor != null && campo.unidad != null ? ' ${campo.unidad}' : ''),
        style: t == 'sin datos' ? tema.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic) : tema.textTheme.bodyMedium,
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 150, child: Text(campo.etiqueta, style: tema.textTheme.labelMedium)),
        Expanded(child: valorWidget),
      ]),
    );
  }
}
