import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/entidades/catalogo.dart';
import 'tema.dart';

/// Submódulo de un pilar: un acceso a una pantalla (genérica o especializada).
class Submodulo {
  const Submodulo(this.titulo, this.ruta, this.icono, this.color, {this.descripcion = '', this.nivel});
  final String titulo;
  final String ruta;
  final IconData icono;
  final Color color;
  final String descripcion;
  final int? nivel;
}

/// Pilar de navegación (D-002). Por dentro, cada pilar corresponde a uno o más de
/// los 8 niveles de la arquitectura (D-001).
class Pilar {
  const Pilar(this.id, this.titulo, this.icono, this.color, this.niveles, this.descripcion, this.submodulos);
  final String id;
  final String titulo;
  final IconData icono;
  final Color color;
  final String niveles;
  final String descripcion;
  final List<Submodulo> submodulos;
}

Submodulo _e(String tabla, {String? titulo}) {
  final d = catalogo[tabla]!;
  return Submodulo(titulo ?? d.plural, '/e/$tabla', d.icono, d.color, descripcion: d.descripcion, nivel: d.nivel);
}

/// Los 9 pilares del menú principal (Prompt Maestro §12). "Inicio" es el tablero.
final List<Pilar> pilares = [
  Pilar('territorio', 'Territorio y ambiente', Icons.terrain, ColoresArea.agroecologia, 'Nivel 1',
      'Suelo, agua, clima y precipitación, relieve y unidades espaciales.', [
    const Submodulo('Mapa', '/mapa', Icons.map, ColoresArea.agroecologia,
        descripcion: 'Vista sobre la información existente. Sin geometría = sin datos.', nivel: 1),
    const Submodulo('Potreros y divisiones', '/potreros', Icons.grass, ColoresArea.agroecologia,
        descripcion: 'Máx. 6 potreros principales; divisiones temporales A1, A2…', nivel: 1),
    _e('destinos_superficie'),
    _e('fuentes_agua'),
    _e('mediciones_ambientales'),
    _e('muestras_suelo'),
    _e('resultados_suelo'),
  ]),
  Pilar('recursos', 'Recursos e infraestructura', Icons.home_work, ColoresArea.infraestructura, 'Nivel 2',
      'Infraestructura, equipos, herramientas, insumos, capacidad humana y mantenimiento.', [
    _e('infraestructuras'),
    _e('recursos'),
  ]),
  Pilar('produccion', 'Producción', Icons.agriculture, ColoresArea.ganaderia, 'Nivel 3',
      'Ganadería, pasturas, pancoger, vivero, silvopastoril, bancos de forraje y compostaje.', [
    _e('sistemas_productivos'),
    const Submodulo('Animales', '/animales', Icons.pets, ColoresArea.ganaderia,
        descripcion: 'Identificación, QR, fotos, lote, peso, producción, reproducción, sanidad e historia.', nivel: 3),
    const Submodulo('Lotes', '/lotes', Icons.groups, ColoresArea.ganaderia,
        descripcion: 'Grupo operativo. Animal ↔ lote es una relación histórica.', nivel: 3),
    const Submodulo('QR', '/qr', Icons.qr_code_scanner, ColoresArea.ganaderia,
        descripcion: 'Identificador físico reutilizable: disponible → asignado → activo → liberado.', nivel: 3),
    const Submodulo('Pastoreo y aforo', '/potreros', Icons.grass, ColoresArea.agroecologia,
        descripcion: 'Entrada, permanencia (máx. 2 días), salida, descanso, aforo y materia seca.', nivel: 3),
    _e('eventos_sanitarios'),
    _e('eventos_reproductivos'),
    _e('produccion_leche'),
    _e('entregas_leche'),
    _e('movimientos_economicos'),
    _e('especies'),
    _e('lotes_vivero'),
    _e('establecimientos'),
  ]),
  Pilar('operaciones', 'Operaciones', Icons.task_alt, ColoresArea.general, 'Nivel 4',
      'Procesos, actividades, tareas, agenda y seguimiento.', [
    const Submodulo('Agenda', '/agenda', Icons.event_note, ColoresArea.general,
        descripcion: 'Vista temporal de actividades y alertas (no es otra base de datos).', nivel: 4),
    _e('actividades'),
  ]),
  Pilar('monitoreo', 'Monitoreo', Icons.monitor_heart, ColoresArea.general, 'Nivel 5',
      'Mediciones, indicadores, señales, tendencias y seguimiento.', [
    const Submodulo('Indicadores y cálculos', '/monitoreo', Icons.functions, ColoresArea.general,
        descripcion: 'Solo fórmulas acordadas; faltante indispensable = no calculable.', nivel: 5),
    _e('alertas'),
    _e('observaciones'),
    _e('evidencias'),
  ]),
  Pilar('analisis', 'Análisis', Icons.insights, ColoresArea.general, 'Nivel 6',
      'Análisis, hallazgos, hipótesis, diagnósticos cuando correspondan e interpretación.', [
    const Submodulo('Informes y tablero', '/informes', Icons.dashboard, ColoresArea.general,
        descripcion: 'Resumen por periodo, gráficos y exportación.', nivel: 6),
    _e('hallazgos'),
    const Submodulo('Asistente de IA', '/ia', Icons.auto_awesome, ColoresArea.general,
        descripcion: 'Explica, señala faltantes, analiza y propone. No inventa ni decide.', nivel: 6),
  ]),
  Pilar('decisiones', 'Decisiones', Icons.gavel, ColoresArea.general, 'Nivel 7',
      'Recomendaciones, alternativas, decisiones y planificación.', [
    _e('recomendaciones'),
    _e('alternativas'),
    _e('decisiones'),
  ]),
  Pilar('mejora', 'Mejora continua', Icons.school, ColoresArea.general, 'Nivel 8',
      'Resultados, verificación, aprendizaje, propuestas de mejora, nuevas versiones y conocimiento validado.', [
    _e('aprendizajes'),
    const Submodulo('Guías y procedimientos', '/guias', Icons.menu_book, ColoresArea.general,
        descripcion: 'Regla de oro: cómo obtener cada dato correctamente. Versionadas.', nivel: 8),
    _e('incidentes_tecnicos'),
  ]),
];

Pilar? pilarPorId(String id) {
  for (final p in pilares) {
    if (p.id == id) return p;
  }
  return null;
}

/// Pantalla de un pilar: sus submódulos con su nivel y propósito.
class PilarPantalla extends StatelessWidget {
  const PilarPantalla({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final p = pilarPorId(id);
    if (p == null) return const Scaffold(body: Center(child: Text('Pilar no encontrado')));
    return Scaffold(
      appBar: AppBar(title: Text(p.titulo)),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          color: p.color.withAlpha(25),
          child: ListTile(
            leading: Icon(p.icono, color: p.color, size: 32),
            title: Text(p.niveles),
            subtitle: Text(p.descripcion),
          ),
        ),
        for (final s in p.submodulos)
          Card(
            child: ListTile(
              leading: Icon(s.icono, color: s.color),
              title: Text(s.titulo),
              subtitle: s.descripcion.isEmpty ? null : Text(s.descripcion, maxLines: 3, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(s.ruta),
            ),
          ),
      ]),
    );
  }
}

/// Menú lateral con los 9 pilares y las funciones transversales.
class MenuPilares extends StatelessWidget {
  const MenuPilares({super.key});

  @override
  Widget build(BuildContext context) {
    void ir(String ruta) {
      Navigator.pop(context);
      context.push(ruta);
    }

    return Drawer(
      child: SafeArea(
        child: ListView(children: [
          const ListTile(title: Text('Sistema Agroecológico Integral', style: TextStyle(fontWeight: FontWeight.bold))),
          ListTile(leading: const Icon(Icons.home), title: const Text('1. Inicio'), onTap: () => Navigator.pop(context)),
          for (var i = 0; i < pilares.length; i++)
            ListTile(
              leading: Icon(pilares[i].icono, color: pilares[i].color),
              title: Text('${i + 2}. ${pilares[i].titulo}'),
              subtitle: Text(pilares[i].niveles),
              onTap: () => ir('/p/${pilares[i].id}'),
            ),
          const Divider(),
          const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('Transversales')),
          ListTile(leading: const Icon(Icons.search), title: const Text('Búsqueda'), onTap: () => ir('/buscar')),
          ListTile(leading: const Icon(Icons.event_note), title: const Text('Agenda'), onTap: () => ir('/agenda')),
          ListTile(leading: const Icon(Icons.map), title: const Text('Mapa'), onTap: () => ir('/mapa')),
          ListTile(leading: const Icon(Icons.dashboard), title: const Text('Resumen e informes'), onTap: () => ir('/informes')),
          ListTile(leading: const Icon(Icons.attach_file), title: const Text('Evidencias'), onTap: () => ir('/e/evidencias')),
          ListTile(leading: const Icon(Icons.auto_awesome), title: const Text('Asistente de IA'), onTap: () => ir('/ia')),
          ListTile(leading: const Icon(Icons.bug_report), title: const Text('Incidencias técnicas'), onTap: () => ir('/e/incidentes_tecnicos')),
          ListTile(leading: const Icon(Icons.settings), title: const Text('Configuración'), onTap: () => ir('/config')),
        ]),
      ),
    );
  }
}
