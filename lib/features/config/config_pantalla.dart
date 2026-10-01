import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/entidades/repo_generico.dart';
import '../../core/finca_actual.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';
import '../guias/guias.dart';
import '../respaldo/respaldo.dart';

final _fincaDetalleProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return null;
  return ref.watch(supabaseProvider).from('fincas').select().eq('id', finca.id).maybeSingle();
});

final criteriosProvider = FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final finca = ref.watch(fincaActualProvider);
  if (finca == null) return const [];
  final r = await ref
      .watch(supabaseProvider)
      .from('criterios_parametros')
      .select()
      .eq('finca_id', finca.id)
      .eq('is_deleted', false)
      .order('vigente_desde', ascending: false);
  return List<Map<String, dynamic>>.from(r);
});

/// Configuración: misión y visión (las escribe el usuario), criterios versionados
/// (estructura ≠ catálogo ≠ criterio ≠ fórmula ≠ guía, §49), datos declarados,
/// guías base, respaldo y miembros.
class ConfigPantalla extends ConsumerStatefulWidget {
  const ConfigPantalla({super.key});
  @override
  ConsumerState<ConfigPantalla> createState() => _ConfigPantallaState();
}

class _ConfigPantallaState extends ConsumerState<ConfigPantalla> {
  final _mision = TextEditingController();
  final _vision = TextEditingController();
  bool _cargado = false;

  @override
  void dispose() {
    _mision.dispose();
    _vision.dispose();
    super.dispose();
  }

  Future<void> _guardarMV() async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    try {
      await ref.read(supabaseProvider).from('fincas').update({
        'mision': _mision.text.trim().isEmpty ? null : _mision.text.trim(),
        'vision': _vision.text.trim().isEmpty ? null : _vision.text.trim(),
      }).eq('id', finca.id);
      ref.invalidate(_fincaDetalleProvider);
      refrescarTodo(ref);
      if (mounted) mostrarMensaje(context, 'Misión y visión guardadas (quedan en la auditoría).');
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  Future<void> _nuevoCriterio() async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    final valor = await pedirTexto(context,
        titulo: 'Consumo de materia seca',
        etiqueta: '% del peso vivo por día',
        ayuda: 'Referencia de la arquitectura: 2–3 % (no es universal). Escriba el suyo.');
    if (valor == null || !mounted) return;
    final n = double.tryParse(valor.replaceAll(',', '.'));
    if (n == null) {
      mostrarMensaje(context, 'Escriba un número.');
      return;
    }
    final fuente = await pedirTexto(context,
        titulo: 'Fuente del criterio', etiqueta: 'De dónde sale este valor', ayuda: 'Obligatoria: asistencia técnica, literatura, experiencia propia…');
    if (fuente == null || !mounted) return;
    try {
      await ref.read(supabaseProvider).from('criterios_parametros').insert({
        'id': nuevoId(),
        'finca_id': finca.id,
        'codigo': 'ms_pct_peso_vivo',
        'nombre': 'Consumo de materia seca (% del peso vivo por día)',
        'valor': n,
        'unidad': '% peso vivo/día',
        'fuente': fuente,
        'limitaciones': 'Referencia configurable; no es una regla universal.',
      });
      ref.invalidate(criteriosProvider);
      if (mounted) mostrarMensaje(context, 'Criterio guardado como nueva versión. Los cálculos anteriores conservan el suyo.');
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  Future<void> _rpc(String funcion, String ok) async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    try {
      final r = await ref.read(repoProvider).rpc(funcion, {'p_finca': finca.id});
      refrescarTodo(ref);
      ref.invalidate(guiasProvider);
      if (mounted) mostrarMensaje(context, '$ok ${r is Map ? (r['resultado'] ?? '') : (r ?? '')}');
    } catch (e) {
      if (mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final f = ref.watch(_fincaDetalleProvider);
    final criterios = ref.watch(criteriosProvider);
    final datos = f.valueOrNull;
    if (datos != null && !_cargado) {
      _mision.text = '${datos['mision'] ?? ''}';
      _vision.text = '${datos['vision'] ?? ''}';
      _cargado = true;
    }
    final usuario = ref.read(supabaseProvider).auth.currentUser;
    return Scaffold(
      appBar: AppBar(title: const Text('Configuración')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Seccion(
          titulo: 'Misión y visión de la finca',
          icono: Icons.flag,
          hijos: [
            const Text('Las escribe usted: el sistema no las inventa.'),
            const SizedBox(height: 8),
            TextField(controller: _mision, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Misión')),
            const SizedBox(height: 8),
            TextField(controller: _vision, minLines: 2, maxLines: 6, decoration: const InputDecoration(labelText: 'Visión')),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(onPressed: _guardarMV, icon: const Icon(Icons.save), label: const Text('Guardar')),
            ),
          ],
        ),
        Seccion(
          titulo: 'Criterios (versionados)',
          icono: Icons.tune,
          accion: IconButton(tooltip: 'Nuevo criterio', icon: const Icon(Icons.add_circle_outline), onPressed: _nuevoCriterio),
          hijos: [
            const Text('Un criterio nuevo no reinterpreta los cálculos anteriores: cada cálculo guarda la versión que usó.'),
            criterios.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text(mensajeError(e)),
              data: (l) => l.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('Sin criterio de consumo de materia seca: la demanda del lote queda "no calculable".'),
                    )
                  : Column(children: [
                      for (final c in l)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${c['nombre']}: ${c['valor']} ${c['unidad']}'),
                          subtitle: Text('Vigente desde ${fechaCorta(c['vigente_desde'])} · Fuente: ${c['fuente']}'),
                        ),
                    ]),
            ),
          ],
        ),
        Seccion(
          titulo: 'Datos de la finca',
          icono: Icons.storage,
          hijos: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.download_done),
              title: const Text('Cargar datos declarados en la arquitectura'),
              subtitle: Text(datos?['datos_declarados_en'] == null
                  ? 'Infraestructura, agua, superficies, sistemas y Potrero 1 (A1–A3).'
                  : 'Cargados el ${fechaCorta(datos?['datos_declarados_en'])}.'),
              onTap: datos?['datos_declarados_en'] == null ? () => _rpc('cargar_datos_declarados', 'Listo:') : null,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.menu_book),
              title: const Text('Crear guías base (regla de oro)'),
              subtitle: const Text('Solo agrega las que falten; quedan en borrador.'),
              onTap: () => _rpc('crear_guias_base', 'Guías creadas:'),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.backup),
              title: const Text('Descargar respaldo completo'),
              subtitle: const Text('Archivo con todas las tablas, incluida la historia. Guárdelo en Google Drive.'),
              onTap: () => descargarRespaldo(context, ref),
            ),
          ],
        ),
        Seccion(
          titulo: 'Cuenta y personas',
          icono: Icons.person,
          hijos: [
            Text('Sesión: ${usuario?.email ?? 'sin sesión'}'),
            const SizedBox(height: 4),
            const Text('Roles y permisos reales: pendientes hasta definir las personas y funciones (34.3). '
                'Hoy todo miembro de la finca puede registrar; todo queda auditado.'),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              OutlinedButton.icon(
                onPressed: () => context.push('/e/incidentes_tecnicos/nuevo?modulo=configuracion'),
                icon: const Icon(Icons.bug_report),
                label: const Text('Reportar problema'),
              ),
              OutlinedButton.icon(
                onPressed: () => ref.read(supabaseProvider).auth.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Salir'),
              ),
            ]),
          ],
        ),
      ]),
    );
  }
}
