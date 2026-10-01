import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/pilares.dart';
import '../../app/tema.dart';
import '../../core/entidades/catalogo.dart';
import '../../core/entidades/definicion.dart';
import '../../core/entidades/repo_generico.dart';
import '../../core/finca_actual.dart';
import '../../core/supabase.dart';
import '../../core/widgets.dart';
import '../ia/ia.dart';
import '../respaldo/respaldo.dart';

const _periodoInicio = PeriodoTablero(null, null);

/// Inicio: tablero vivo de la finca. Todo lo que muestra son vistas sobre los
/// mismos datos (D-019); todo se puede tocar para profundizar.
class InicioPantalla extends ConsumerWidget {
  const InicioPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fincas = ref.watch(fincasProvider);
    final finca = ref.watch(fincaActualProvider);
    return Scaffold(
      drawer: finca == null ? null : const MenuPilares(),
      appBar: AppBar(
        title: Text(finca?.nombre ?? 'Finca'),
        actions: [
          if (finca != null) ...[
            IconButton(tooltip: 'Buscar', icon: const Icon(Icons.search), onPressed: () => context.push('/buscar')),
            IconButton(
              tooltip: 'Asistente de IA',
              icon: const Icon(Icons.auto_awesome),
              onPressed: () => AsistenteIA.abrir(context, titulo: finca.nombre),
            ),
          ],
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'respaldo':
                  descargarRespaldo(context, ref);
                case 'incidencia':
                  context.push('/e/incidentes_tecnicos/nuevo?modulo=inicio&pantalla=inicio');
                case 'config':
                  context.push('/config');
                case 'salir':
                  ref.read(supabaseProvider).auth.signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'respaldo', child: Text('Descargar respaldo')),
              PopupMenuItem(value: 'incidencia', child: Text('Reportar un problema de la app')),
              PopupMenuItem(value: 'config', child: Text('Configuración')),
              PopupMenuItem(value: 'salir', child: Text('Salir')),
            ],
          ),
        ],
      ),
      body: fincas.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Vacio(mensajeError(e)),
        data: (lista) => lista.isEmpty ? const _CrearFinca() : const _Tablero(),
      ),
    );
  }
}

class _Tablero extends ConsumerWidget {
  const _Tablero();

  Future<void> _rpc(BuildContext context, WidgetRef ref, String funcion, String ok) async {
    final finca = ref.read(fincaActualProvider);
    if (finca == null) return;
    try {
      await ref.read(repoProvider).rpc(funcion, {'p_finca': finca.id});
      refrescarTodo(ref);
      if (context.mounted) mostrarMensaje(context, ok);
    } catch (e) {
      if (context.mounted) mostrarMensaje(context, mensajeError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(tableroProvider(_periodoInicio));
    return t.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Vacio(mensajeError(e)),
      data: (d) {
        final ancho = MediaQuery.of(context).size.width;
        final columnas = ancho > 1000 ? 4 : (ancho > 640 ? 3 : 2);
        final finca = Map<String, dynamic>.from((d['finca'] as Map?) ?? const {});
        final animales = Map<String, dynamic>.from((d['animales'] as Map?) ?? const {});
        final territorio = Map<String, dynamic>.from((d['territorio'] as Map?) ?? const {});
        final alertas = Map<String, dynamic>.from((d['alertas'] as Map?) ?? const {});
        final actividades = Map<String, dynamic>.from((d['actividades'] as Map?) ?? const {});
        final lluvia = Map<String, dynamic>.from((d['lluvia'] as Map?) ?? const {});
        final leche = Map<String, dynamic>.from((d['leche'] as Map?) ?? const {});
        final aforos = List<Map>.from((d['aforos'] as List?) ?? const []);
        final ocupaciones = List<Map>.from((d['ocupaciones_activas'] as List?) ?? const []);
        final flujo = List<Map>.from((d['flujo'] as List?) ?? const []);
        final guias = Map<String, dynamic>.from((d['guias'] as Map?) ?? const {});
        final listaAlertas = List<Map>.from((alertas['lista'] as List?) ?? const []);
        final proximas = List<Map>.from((actividades['proximas'] as List?) ?? const []);

        return RefreshIndicator(
          onRefresh: () async => refrescarTodo(ref),
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
            _Proposito(finca: finca),
            if (finca['datos_declarados_en'] == null)
              Card(
                color: ColoresArea.agroecologia.withAlpha(25),
                child: ListTile(
                  leading: const Icon(Icons.download_done, color: ColoresArea.agroecologia),
                  title: const Text('Cargar los datos que ya declaró en la arquitectura'),
                  subtitle: const Text(
                      'Vivienda, cercas, corral de embarque, corral proyectado, láminas de zinc, nacimientos, '
                      '33 ha (pancoger 4, banco de forraje 4 proyectado, bosque ≈4, humedal ≈1, ganadería ≈20 por resta) '
                      'y Potrero 1 con A1, A2, A3. Lo aproximado queda como estimado.'),
                  onTap: () => _rpc(context, ref, 'cargar_datos_declarados', 'Datos declarados cargados.'),
                ),
              ),
            if ((guias['total'] ?? 0) == 0)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: const Text('Crear las guías base (regla de oro)'),
                  subtitle: const Text('Suelo, aforo, lluvia, pesaje, pastoreo, sanidad, fotografía, ubicación y demanda de MS.'),
                  onTap: () => _rpc(context, ref, 'crear_guias_base', 'Guías base creadas en borrador.'),
                ),
              ),
            // Atención: alertas y agenda
            Seccion(
              titulo: 'Requiere atención (${alertas['abiertas'] ?? 0} alertas)',
              icono: Icons.warning_amber,
              accion: TextButton(onPressed: () => context.push('/e/alertas'), child: const Text('Ver todas')),
              hijos: [
                if (listaAlertas.isEmpty) const Text('Sin alertas abiertas. Las reglas se revisan cada vez que abre el inicio.'),
                for (final a in listaAlertas.take(5))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.error_outline),
                    title: Text('${a['mensaje']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${etiquetaDe('${a['tipo']}')} · ${fechaCorta(a['creada'])}'),
                    onTap: () => context.push('/e/alertas/${a['id']}'),
                  ),
              ],
            ),
            Seccion(
              titulo: 'Agenda',
              icono: Icons.event_note,
              accion: TextButton(onPressed: () => context.push('/agenda'), child: const Text('Abrir agenda')),
              hijos: [
                Wrap(spacing: 8, runSpacing: 4, children: [
                  ChipEstado('Vencidas: ${actividades['vencidas'] ?? 0}', icono: Icons.schedule),
                  ChipEstado('Por verificar: ${actividades['por_verificar'] ?? 0}', icono: Icons.fact_check),
                ]),
                if (proximas.isEmpty) const Text('Sin actividades pendientes.'),
                for (final a in proximas.take(6))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(a['vencida'] == true ? Icons.alarm : Icons.radio_button_unchecked),
                    title: Text('${a['titulo']}', maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                        '${etiquetaDe('${a['estado']}')} · ${a['sin_fecha'] == true ? 'sin fecha' : fechaCorta(a['fecha'])}${a['vencida'] == true ? ' · vencida' : ''}'),
                    onTap: () => context.push('/e/actividades/${a['id']}'),
                  ),
              ],
            ),
            // Cifras
            GridView.count(
              crossAxisCount: columnas,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.6,
              children: [
                Cifra(
                  titulo: 'Animales activos',
                  valor: '${animales['total'] ?? 0}',
                  nota: 'Con peso: ${animales['con_peso'] ?? 0}',
                  icono: Icons.pets,
                  color: ColoresArea.ganaderia,
                  alTocar: () => context.push('/animales'),
                ),
                Cifra(
                  titulo: 'Lotes',
                  valor: '${d['lotes'] ?? 0}',
                  icono: Icons.groups,
                  color: ColoresArea.ganaderia,
                  alTocar: () => context.push('/lotes'),
                ),
                Cifra(
                  titulo: 'Potreros / divisiones',
                  valor: '${territorio['potreros'] ?? 0} / ${territorio['divisiones'] ?? 0}',
                  nota: 'Máx. 6 potreros',
                  icono: Icons.grass,
                  color: ColoresArea.agroecologia,
                  alTocar: () => context.push('/potreros'),
                ),
                Cifra(
                  titulo: 'Lotes pastoreando',
                  valor: '${ocupaciones.length}',
                  nota: ocupaciones.any((o) => o['excede'] == true) ? 'Alguno supera el límite' : 'Dentro del límite',
                  icono: Icons.timer,
                  color: ColoresArea.agroecologia,
                  alTocar: () => context.push('/potreros'),
                ),
                Cifra(
                  titulo: 'Último aforo',
                  valor: aforos.isEmpty
                      ? 'sin datos'
                      : valorONo(aforos.first['ms_pct'] as num?, unidad: '% MS', faltante: 'no calculable'),
                  nota: aforos.isEmpty
                      ? null
                      : 'Agua ${valorONo(aforos.first['agua_pct'] as num?, unidad: '%', faltante: 'no calculable')} · ${aforos.first['unidad'] ?? ''}',
                  icono: Icons.science,
                  color: ColoresArea.agroecologia,
                  alTocar: () => context.push('/potreros'),
                ),
                Cifra(
                  titulo: 'Lluvia (30 días)',
                  valor: valorONo(lluvia['total_mm'] as num?, unidad: 'mm'),
                  nota: '${lluvia['registros'] ?? 0} registros · 1 mm = 1 L/m²',
                  icono: Icons.thunderstorm,
                  color: ColoresArea.agroecologia,
                  alTocar: () => context.push('/e/mediciones_ambientales'),
                ),
                Cifra(
                  titulo: 'Leche (30 días)',
                  valor: valorONo(leche['total_litros'] as num?, unidad: 'L'),
                  nota: 'Entregado: ${valorONo(leche['entregado_litros'] as num?, unidad: 'L')}',
                  icono: Icons.local_drink,
                  color: ColoresArea.ganaderia,
                  alTocar: () => context.push('/e/produccion_leche'),
                ),
                Cifra(
                  titulo: 'Sanidad abierta',
                  valor: '${d['sanidad_abiertos'] ?? 0}',
                  nota: 'Observación ≠ diagnóstico',
                  icono: Icons.medical_services,
                  color: ColoresArea.ganaderia,
                  alTocar: () => context.push('/e/eventos_sanitarios'),
                ),
              ],
            ),
            // Flujo dato → mejora (§8)
            Seccion(
              titulo: 'Del dato a la mejora',
              icono: Icons.account_tree,
              hijos: [
                Text('Dato → cálculo → alerta/señal → hallazgo → recomendación → decisión → actividad → verificación → aprendizaje',
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (var i = 0; i < flujo.length; i++)
                    ActionChip(
                      avatar: CircleAvatar(child: Text('${i + 1}', style: const TextStyle(fontSize: 11))),
                      label: Text('${flujo[i]['etapa']}: ${flujo[i]['valor']}'),
                      onPressed: () => context.push('${flujo[i]['ruta']}'),
                    ),
                ]),
              ],
            ),
            // Pilares
            Seccion(
              titulo: 'Módulos (9 pilares, 8 niveles)',
              icono: Icons.apps,
              accion: TextButton(onPressed: () => context.push('/informes'), child: const Text('Informes')),
              hijos: [
                GridView.count(
                  crossAxisCount: columnas,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  childAspectRatio: 1.5,
                  children: [
                    for (final p in pilares)
                      Card(
                        color: p.color.withAlpha(20),
                        child: InkWell(
                          onTap: () => context.push('/p/${p.id}'),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(p.icono, color: p.color, size: 30),
                              const SizedBox(height: 4),
                              Text(p.titulo, textAlign: TextAlign.center, maxLines: 2),
                              Text(p.niveles, style: Theme.of(context).textTheme.bodySmall),
                            ]),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
            Seccion(
              titulo: 'Atajos de campo',
              icono: Icons.bolt,
              hijos: [
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final a in const [
                    ['Escanear QR', '/qr', Icons.qr_code_scanner],
                    ['Registrar lluvia', '/e/mediciones_ambientales/nuevo?variable=precipitacion&unidad=mm&naturaleza=medido', Icons.thunderstorm],
                    ['Observación sanitaria', '/e/eventos_sanitarios/nuevo?tipo=observacion&etapa=observacion', Icons.medical_services],
                    ['Leche del día', '/e/produccion_leche/nuevo?naturaleza=medido', Icons.local_drink],
                    ['Nueva actividad', '/e/actividades/nuevo', Icons.add_task],
                    ['Gasto / costo', '/e/movimientos_economicos/nuevo', Icons.payments],
                  ])
                    ActionChip(
                      avatar: Icon(a[2] as IconData, size: 18),
                      label: Text(a[0] as String),
                      onPressed: () => context.push(a[1] as String),
                    ),
                ]),
              ],
            ),
            if (catalogo.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Actualizado ${fechaCorta((d['periodo'] as Map?)?['generado_en'])}. Los valores vacíos dicen "sin datos": nunca se muestran como 0.',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ),
          ]),
        );
      },
    );
  }
}

/// Propósito del sistema (Prompt Maestro §0–§1) y misión/visión que escribe el usuario.
class _Proposito extends StatelessWidget {
  const _Proposito({required this.finca});
  final Map<String, dynamic> finca;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final mision = '${finca['mision'] ?? ''}'.trim();
    final vision = '${finca['vision'] ?? ''}'.trim();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sistema Agroecológico Integral', style: tema.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Gestionar la finca como un sistema integrado: dato → información → análisis → apoyo a decisión → acción → '
            'resultado → verificación → aprendizaje.',
            style: tema.textTheme.bodySmall,
          ),
          const Divider(),
          Text('Misión', style: tema.textTheme.labelLarge),
          Text(mision.isEmpty ? 'Sin definir (escríbala en Configuración)' : mision,
              style: mision.isEmpty ? tema.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic) : null),
          const SizedBox(height: 6),
          Text('Visión', style: tema.textTheme.labelLarge),
          Text(vision.isEmpty ? 'Sin definir (escríbala en Configuración)' : vision,
              style: vision.isEmpty ? tema.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic) : null),
          if (mision.isEmpty || vision.isEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => context.push('/config'),
                icon: const Icon(Icons.edit),
                label: const Text('Escribir misión y visión'),
              ),
            ),
        ]),
      ),
    );
  }
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
