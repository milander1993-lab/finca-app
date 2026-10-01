import 'package:flutter/material.dart';

/// Tipos de campo que el motor genérico sabe capturar y mostrar.
enum TipoCampo {
  texto,
  textoLargo,
  entero,
  decimal,
  fecha,
  fechaHora,
  opcion,
  referencia,
  booleano,
  naturaleza,
  calidad,
}

/// Un campo de una entidad. La autoridad de las reglas está en la base de datos;
/// esto solo guía la captura (obligatorio, unidad, ayuda) y la lectura.
class CampoDef {
  const CampoDef(
    this.clave,
    this.etiqueta, {
    this.tipo = TipoCampo.texto,
    this.obligatorio = false,
    this.opciones = const [],
    this.unidad,
    this.ayuda,
    this.refTabla,
    this.refEtiqueta,
    this.refFiltro,
    this.enLista = false,
    this.soloLectura = false,
    this.enFormulario = true,
  });

  final String clave;
  final String etiqueta;
  final TipoCampo tipo;
  final bool obligatorio;
  final List<String> opciones;
  final String? unidad;
  final String? ayuda;

  /// Para [TipoCampo.referencia]: tabla y columna que se muestra.
  final String? refTabla;
  final String? refEtiqueta;

  /// Filtro opcional de la referencia: columna → valor (p. ej. tipo = potrero).
  final Map<String, String>? refFiltro;

  /// Se muestra como subtítulo en la lista.
  final bool enLista;
  final bool soloLectura;
  final bool enFormulario;
}

/// Entidad hija que se muestra dentro del expediente (relación).
class RelacionDef {
  const RelacionDef(this.tabla, this.campoFk, this.etiqueta);
  final String tabla;
  final String campoFk;
  final String etiqueta;
}

/// Definición declarativa de un módulo/entidad.
class EntidadDef {
  const EntidadDef({
    required this.tabla,
    required this.singular,
    required this.plural,
    required this.icono,
    required this.color,
    required this.nivel,
    required this.campos,
    required this.campoTitulo,
    this.descripcion = '',
    this.campoEstado,
    this.transiciones = const {},
    this.camposPorEstado = const {},
    this.estadoInicial,
    this.guiaCodigo,
    this.orden = 'created_at',
    this.relaciones = const [],
    this.tieneMotivoAnulacion = true,
    this.prefijoTitulo = '',
  });

  final String tabla;
  final String singular;
  final String plural;
  final IconData icono;
  final Color color;

  /// Nivel de la arquitectura (1–8).
  final int nivel;
  final String descripcion;
  final List<CampoDef> campos;
  final String campoTitulo;
  final String prefijoTitulo;

  /// Columna de estado (si la entidad tiene máquina de estados).
  final String? campoEstado;

  /// Transiciones que la interfaz ofrece. El servidor es la autoridad: si
  /// una transición no es válida, la base la rechaza y se muestra el motivo.
  final Map<String, List<String>> transiciones;

  /// Campos que se piden al pasar a un estado (p. ej. ejecutada → resultado).
  final Map<String, List<String>> camposPorEstado;
  final String? estadoInicial;

  /// Guía de la regla de oro asociada a la captura.
  final String? guiaCodigo;
  final String orden;
  final List<RelacionDef> relaciones;
  final bool tieneMotivoAnulacion;

  CampoDef? campo(String clave) {
    for (final c in campos) {
      if (c.clave == clave) return c;
    }
    return null;
  }

  String tituloDe(Map<String, dynamic> fila) {
    final v = fila[campoTitulo];
    final t = (v == null || '$v'.trim().isEmpty) ? '(sin título)' : textoValor(campo(campoTitulo), v);
    return prefijoTitulo.isEmpty ? t : '$prefijoTitulo$t';
  }

  String subtituloDe(Map<String, dynamic> fila) {
    final partes = <String>[];
    for (final c in campos.where((c) => c.enLista)) {
      final v = fila[c.clave];
      if (v == null || '$v'.isEmpty) continue;
      if (c.tipo == TipoCampo.referencia) continue;
      partes.add(textoValor(c, v) + (c.unidad != null ? ' ${c.unidad}' : ''));
    }
    return partes.join(' · ');
  }
}

/// Convierte "fuera_de_servicio" en "Fuera de servicio".
String etiquetaDe(String? valor) {
  if (valor == null || valor.isEmpty) return 'sin datos';
  const especiales = {
    'senal': 'Señal',
    'hipotesis': 'Hipótesis',
    'diagnostico': 'Diagnóstico',
    'diagnostico_profesional': 'Diagnóstico profesional',
    'diagnostico_gestacion': 'Diagnóstico de gestación',
    'revision': 'Revisión',
    'observacion': 'Observación',
    'decision': 'Decisión',
    'ejecutandose': 'Ejecutándose',
    'conservacion': 'Conservación',
    'ganaderia': 'Ganadería',
    'requiere_verificacion': 'Requiere verificación',
    'verificacion': 'Verificación',
    'precipitacion': 'Precipitación (lluvia)',
    'fosforo_bray_ii': 'Fósforo Bray II',
    'saturacion_aluminio': 'Saturación de aluminio',
    'ph_agua': 'pH en agua',
    'materia_organica': 'Materia orgánica',
    'pendiente_verificacion': 'Pendiente de verificación',
    'en_construccion': 'En construcción',
    'reparacion': 'Reparación',
    'palpacion': 'Palpación',
    'vacunacion': 'Vacunación',
    'desparasitacion': 'Desparasitación',
    'endoparasitos': 'Endoparásitos',
    'ectoparasitos': 'Ectoparásitos',
    'captacion': 'Captación',
    'conduccion': 'Conducción',
    'distribucion': 'Distribución',
    'escorrentia': 'Escorrentía',
    'zona_concentracion': 'Zona de concentración',
    'cuenta_por_cobrar': 'Cuenta por cobrar',
    'cuenta_por_pagar': 'Cuenta por pagar',
    'capacidad_humana': 'Capacidad humana',
    'en_propagacion': 'En propagación',
    'produccion': 'Producción',
    'pendiente_sincronizacion': 'Pendiente de subir a Drive',
    'informe_laboratorio': 'Informe de laboratorio',
    'solucion_propuesta': 'Solución propuesta',
    'intervencion_requerida': 'Intervención requerida',
    'sincronizacion': 'Sincronización',
    'convertida_actividad': 'Convertida en actividad',
    'convertida_decision': 'Convertida en decisión',
    'convertida_hallazgo': 'Convertida en hallazgo',
    'en_analisis': 'En análisis',
    'en_revision': 'En revisión',
    'no_aplica': 'No aplica',
    'no_disponible': 'No disponible',
    'no_intervencion': 'No intervención',
    'solicitar_informacion': 'Solicitar información',
    'seleccionar_alternativa': 'Seleccionar alternativa',
    'nueva_version': 'Nueva versión',
    'banco_forraje': 'Banco de forraje',
    'corral_embarque': 'Corral de embarque',
    'tratamiento_autorizado': 'Tratamiento autorizado',
    'en_establecimiento': 'En establecimiento',
  };
  if (especiales.containsKey(valor)) return especiales[valor]!;
  final t = valor.replaceAll('_', ' ');
  return t[0].toUpperCase() + t.substring(1);
}

/// Texto legible de un valor según su tipo. Nunca convierte vacío en 0.
String textoValor(CampoDef? c, Object? v) {
  if (v == null || (v is String && v.trim().isEmpty)) return 'sin datos';
  if (c == null) return '$v';
  switch (c.tipo) {
    case TipoCampo.booleano:
      return v == true ? 'Sí' : 'No';
    case TipoCampo.fecha:
    case TipoCampo.fechaHora:
      final d = DateTime.tryParse('$v');
      if (d == null) return '$v';
      final l = d.toLocal();
      String dos(int n) => n.toString().padLeft(2, '0');
      final f = '${l.year}-${dos(l.month)}-${dos(l.day)}';
      return c.tipo == TipoCampo.fecha ? f : '$f ${dos(l.hour)}:${dos(l.minute)}';
    case TipoCampo.opcion:
    case TipoCampo.naturaleza:
    case TipoCampo.calidad:
      return etiquetaDe('$v');
    case TipoCampo.decimal:
      final n = num.tryParse('$v');
      if (n == null) return '$v';
      return n == n.roundToDouble() ? n.toInt().toString() : n.toString();
    default:
      if (v is Map || v is List) return v.toString();
      return '$v';
  }
}
