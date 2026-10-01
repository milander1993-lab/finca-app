import 'package:flutter/material.dart';

import '../../app/tema.dart';
import 'definicion.dart';

// Atajos de campos frecuentes ------------------------------------------------
const _naturaleza = CampoDef('naturaleza', 'Naturaleza del dato', tipo: TipoCampo.naturaleza, obligatorio: true,
    ayuda: 'observado, medido, estimado, calculado, externo, pronosticado o validado');
const _calidad = CampoDef('estado_calidad', 'Calidad del dato', tipo: TipoCampo.calidad);
const _notaCalidad = CampoDef('nota_calidad', 'Nota de calidad', tipo: TipoCampo.textoLargo,
    ayuda: 'Obligatoria si el estado es en revisión, inconsistente, rechazado, corregido o reemplazado');
const _fechaHecho = CampoDef('fecha_hecho', 'Fecha del hecho', tipo: TipoCampo.fechaHora, obligatorio: true,
    ayuda: 'Cuándo ocurrió (no cuándo se registra)');
const _descripcion = CampoDef('descripcion', 'Descripción', tipo: TipoCampo.textoLargo);
const _unidad = CampoDef('unidad_id', 'Unidad espacial (potrero, división…)', tipo: TipoCampo.referencia,
    refTabla: 'unidades_espaciales', refEtiqueta: 'nombre');
const _animal = CampoDef('animal_id', 'Animal', tipo: TipoCampo.referencia, refTabla: 'animales', refEtiqueta: 'numero_interno');
const _lote = CampoDef('lote_id', 'Lote', tipo: TipoCampo.referencia, refTabla: 'lotes_ganaderos', refEtiqueta: 'nombre');
const _objetoTipo = CampoDef('objeto_tipo', 'Tipo de objeto vinculado', soloLectura: true);
const _objetoId = CampoDef('objeto_id', 'Objeto vinculado', soloLectura: true, enFormulario: false);

const _estadosActividad = {
  'programada': ['disponible', 'iniciada', 'ejecutada', 'reprogramada', 'bloqueada', 'cancelada', 'no_aplica'],
  'pendiente': ['programada', 'disponible', 'iniciada', 'ejecutada', 'bloqueada', 'cancelada', 'no_aplica'],
  'disponible': ['iniciada', 'ejecutada', 'reprogramada', 'bloqueada', 'cancelada'],
  'iniciada': ['pausada', 'ejecutada', 'parcial', 'bloqueada', 'cancelada'],
  'pausada': ['reanudada', 'cancelada'],
  'reanudada': ['pausada', 'ejecutada', 'parcial'],
  'parcial': ['iniciada', 'ejecutada', 'reprogramada'],
  'bloqueada': ['pendiente', 'programada', 'cancelada'],
  'reprogramada': ['programada', 'disponible', 'iniciada', 'ejecutada'],
  'requiere_verificacion': ['verificada', 'iniciada'],
  'verificada': ['cerrada'],
  'cancelada': ['cerrada'],
  'no_aplica': ['cerrada'],
};

/// Catálogo de módulos genéricos (niveles 1–8 + transversales).
/// Las pantallas especializadas (animales, lotes, potreros, aforo, QR, mapa) siguen aparte.
final Map<String, EntidadDef> catalogo = {
  for (final d in <EntidadDef>[
    // ── NIVEL 1: BASE FÍSICA Y AMBIENTAL ──────────────────────────────────
    const EntidadDef(
      tabla: 'fuentes_agua', singular: 'Fuente o elemento de agua', plural: 'Agua',
      descripcion: 'Nacimiento → escorrentía → humedal → canal → conducción → captación → almacenamiento → distribución → uso. No se asumen ríos ni infraestructura no declarada.',
      icono: Icons.water_drop, color: ColoresArea.agroecologia, nivel: 1, campoTitulo: 'nombre',
      campoEstado: 'estado', guiaCodigo: 'georreferenciacion', orden: 'nombre',
      transiciones: {
        'pendiente_verificacion': ['existente', 'operativo', 'proyectado'],
        'existente': ['operativo', 'fuera_de_servicio'],
        'operativo': ['fuera_de_servicio'],
        'fuera_de_servicio': ['operativo'],
        'proyectado': ['existente'],
      },
      campos: [
        CampoDef('nombre', 'Nombre', obligatorio: true),
        CampoDef('tipo', 'Tipo', tipo: TipoCampo.opcion, obligatorio: true, enLista: true, opciones: [
          'nacimiento', 'escorrentia', 'zona_concentracion', 'humedal', 'canal', 'conduccion', 'captacion',
          'almacenamiento', 'distribucion', 'uso', 'otro'
        ]),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, enLista: true,
            opciones: ['pendiente_verificacion', 'existente', 'operativo', 'fuera_de_servicio', 'proyectado']),
        CampoDef('conservacion', 'Elemento de conservación', tipo: TipoCampo.booleano,
            ayuda: 'No declara una categoría legal de protección'),
        _unidad,
        CampoDef('latitud', 'Latitud', tipo: TipoCampo.decimal, ayuda: 'Grados decimales (vacío = sin georreferenciar)'),
        CampoDef('longitud', 'Longitud', tipo: TipoCampo.decimal),
        CampoDef('precision_m', 'Precisión', tipo: TipoCampo.decimal, unidad: 'm'),
        CampoDef('metodo_ubicacion', 'Método de ubicación', ayuda: 'GPS del teléfono, recorrido… (cartografía operativa, no levantamiento legal)'),
        _naturaleza,
        _descripcion,
      ],
    ),
    const EntidadDef(
      tabla: 'mediciones_ambientales', singular: 'Medición de clima o agua', plural: 'Lluvia y clima',
      descripcion: '1 mm de lluvia sobre 1 m² = 1 litro. Distinguir medición local, fuente externa, histórico, modelado y pronóstico.',
      icono: Icons.thunderstorm, color: ColoresArea.agroecologia, nivel: 1, campoTitulo: 'variable',
      guiaCodigo: 'lluvia', orden: 'fecha_hecho',
      campos: [
        CampoDef('variable', 'Variable', tipo: TipoCampo.opcion, obligatorio: true,
            opciones: ['precipitacion', 'temperatura', 'humedad_relativa', 'caudal', 'otra']),
        CampoDef('variable_otra', 'Si es otra, cuál'),
        _fechaHecho,
        CampoDef('valor', 'Valor', tipo: TipoCampo.decimal, obligatorio: true, enLista: true),
        CampoDef('unidad', 'Unidad', obligatorio: true, enLista: true, ayuda: 'Lluvia siempre en mm'),
        _naturaleza,
        CampoDef('fuente', 'Fuente', ayuda: 'Pluviómetro propio, entidad externa, modelo…'),
        CampoDef('metodo', 'Método'),
        _unidad,
        CampoDef('fuente_agua_id', 'Fuente de agua (caudal)', tipo: TipoCampo.referencia, refTabla: 'fuentes_agua', refEtiqueta: 'nombre'),
        _calidad,
        _notaCalidad,
      ],
    ),
    const EntidadDef(
      tabla: 'muestras_suelo', singular: 'Muestra de suelo', plural: 'Suelo',
      descripcion: 'Toma de muestra → envío al laboratorio → resultados. Un resultado de laboratorio no produce automáticamente una recomendación de fertilización.',
      icono: Icons.landscape, color: ColoresArea.agroecologia, nivel: 1, campoTitulo: 'etiqueta',
      campoEstado: 'estado', guiaCodigo: 'muestreo_suelo', orden: 'fecha_hecho',
      transiciones: {'tomada': ['enviada'], 'enviada': ['resultado_recibido']},
      relaciones: [RelacionDef('resultados_suelo', 'muestra_id', 'Resultados de laboratorio')],
      campos: [
        CampoDef('etiqueta', 'Etiqueta de la muestra', obligatorio: true),
        _unidad,
        _fechaHecho,
        CampoDef('numero_puntos', 'Número de puntos', tipo: TipoCampo.entero, ayuda: 'La guía indica aprox. 15–20'),
        CampoDef('profundidad_cm', 'Profundidad', tipo: TipoCampo.decimal, unidad: 'cm'),
        CampoDef('metodo', 'Método'),
        CampoDef('laboratorio', 'Laboratorio'),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, enLista: true, opciones: ['tomada', 'enviada', 'resultado_recibido']),
        CampoDef('observaciones', 'Observaciones', tipo: TipoCampo.textoLargo),
      ],
    ),
    const EntidadDef(
      tabla: 'resultados_suelo', singular: 'Resultado de laboratorio', plural: 'Resultados de suelo',
      icono: Icons.science, color: ColoresArea.agroecologia, nivel: 1, campoTitulo: 'parametro',
      campos: [
        CampoDef('muestra_id', 'Muestra', tipo: TipoCampo.referencia, obligatorio: true, refTabla: 'muestras_suelo', refEtiqueta: 'etiqueta'),
        CampoDef('parametro', 'Parámetro', tipo: TipoCampo.opcion, obligatorio: true, opciones: [
          'ph_agua', 'fosforo_bray_ii', 'saturacion_aluminio', 'aluminio', 'materia_organica', 'calcio', 'magnesio',
          'potasio', 'textura', 'otro'
        ]),
        CampoDef('parametro_otro', 'Si es otro, cuál'),
        CampoDef('valor', 'Valor', tipo: TipoCampo.decimal, enLista: true),
        CampoDef('valor_texto', 'Valor (texto, p. ej. textura)', enLista: true),
        CampoDef('unidad', 'Unidad', enLista: true),
        CampoDef('metodo_laboratorio', 'Método del laboratorio'),
        _naturaleza,
        CampoDef('fuente', 'Fuente (informe)'),
        _calidad,
        _notaCalidad,
      ],
    ),
    // ── NIVEL 2: CAPACIDAD DE MANEJO ───────────────────────────────────────
    const EntidadDef(
      tabla: 'infraestructuras', singular: 'Infraestructura', plural: 'Infraestructura',
      descripcion: 'Falla → alerta → reparación → verificación → retorno a servicio. Una recurrencia es un nuevo incidente. No se agregan dimensiones ni costos no proporcionados.',
      icono: Icons.home_work, color: ColoresArea.infraestructura, nivel: 2, campoTitulo: 'nombre', campoEstado: 'estado',
      orden: 'nombre',
      transiciones: {
        'pendiente_verificacion': ['existente', 'operativo', 'fuera_de_servicio', 'proyectado'],
        'existente': ['operativo', 'fuera_de_servicio', 'mantenimiento', 'reparacion'],
        'operativo': ['fuera_de_servicio', 'mantenimiento', 'reparacion'],
        'fuera_de_servicio': ['reparacion', 'mantenimiento', 'reparado'],
        'mantenimiento': ['reparado', 'operativo'],
        'reparacion': ['reparado'],
        'proyectado': ['en_construccion'],
        'en_construccion': ['existente', 'operativo'],
      },
      campos: [
        CampoDef('nombre', 'Nombre', obligatorio: true),
        CampoDef('tipo', 'Tipo', obligatorio: true, enLista: true, ayuda: 'vivienda, cerca, corral, bodega… (catálogo abierto)'),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, enLista: true, opciones: [
          'existente', 'operativo', 'fuera_de_servicio', 'mantenimiento', 'reparacion', 'reparado', 'proyectado',
          'en_construccion', 'pendiente_verificacion'
        ]),
        _unidad,
        CampoDef('latitud', 'Latitud', tipo: TipoCampo.decimal),
        CampoDef('longitud', 'Longitud', tipo: TipoCampo.decimal),
        _naturaleza,
        _descripcion,
      ],
    ),
    const EntidadDef(
      tabla: 'recursos', singular: 'Recurso', plural: 'Equipos, herramientas e insumos',
      descripcion: 'Requerido → disponible → reservado → recibido → entregado → utilizado. Cantidad vacía = sin datos.',
      icono: Icons.handyman, color: ColoresArea.infraestructura, nivel: 2, campoTitulo: 'nombre', campoEstado: 'estado',
      orden: 'nombre',
      transiciones: {
        'requerido': ['disponible', 'reservado', 'recibido'],
        'disponible': ['reservado', 'entregado', 'utilizado', 'fuera_de_servicio', 'mantenimiento'],
        'reservado': ['recibido', 'entregado', 'disponible'],
        'recibido': ['disponible', 'entregado'],
        'entregado': ['utilizado'],
        'operativo': ['fuera_de_servicio', 'mantenimiento'],
        'fuera_de_servicio': ['mantenimiento', 'operativo'],
        'mantenimiento': ['operativo'],
      },
      campos: [
        CampoDef('nombre', 'Nombre', obligatorio: true),
        CampoDef('clase', 'Clase', tipo: TipoCampo.opcion, obligatorio: true, enLista: true,
            opciones: ['equipo', 'herramienta', 'insumo', 'material', 'capacidad_humana', 'otro']),
        CampoDef('cantidad', 'Cantidad', tipo: TipoCampo.decimal, enLista: true),
        CampoDef('unidad', 'Unidad'),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, enLista: true, opciones: [
          'requerido', 'disponible', 'reservado', 'recibido', 'entregado', 'utilizado', 'operativo',
          'fuera_de_servicio', 'mantenimiento', 'pendiente_verificacion'
        ]),
        CampoDef('infraestructura_id', 'Ubicado en', tipo: TipoCampo.referencia, refTabla: 'infraestructuras', refEtiqueta: 'nombre'),
        _naturaleza,
        _descripcion,
      ],
    ),
    // ── NIVEL 3: SISTEMAS PRODUCTIVOS ──────────────────────────────────────
    const EntidadDef(
      tabla: 'sistemas_productivos', singular: 'Sistema productivo', plural: 'Sistemas productivos',
      descripcion: 'Ganadería, pasturas, pancoger, vivero, silvopastoril, bancos de forraje, compostaje y conservación.',
      icono: Icons.agriculture, color: ColoresArea.agroecologia, nivel: 3, campoTitulo: 'nombre', campoEstado: 'estado',
      orden: 'tipo',
      transiciones: {
        'proyectado': ['en_establecimiento', 'activo'],
        'en_establecimiento': ['activo', 'suspendido'],
        'activo': ['suspendido'],
        'suspendido': ['activo'],
        'pendiente_verificacion': ['activo', 'proyectado'],
      },
      campos: [
        CampoDef('nombre', 'Nombre', obligatorio: true),
        CampoDef('tipo', 'Tipo', tipo: TipoCampo.opcion, obligatorio: true, enLista: true, opciones: [
          'ganaderia', 'pasturas', 'pancoger', 'vivero', 'silvopastoril', 'banco_forraje', 'compostaje', 'conservacion', 'otro'
        ]),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, enLista: true,
            opciones: ['activo', 'proyectado', 'en_establecimiento', 'suspendido', 'pendiente_verificacion']),
        CampoDef('superficie_ha', 'Superficie', tipo: TipoCampo.decimal, unidad: 'ha', enLista: true),
        CampoDef('superficie_naturaleza', 'Naturaleza de la superficie', tipo: TipoCampo.naturaleza,
            ayuda: 'Obligatoria si hay superficie'),
        _unidad,
        _descripcion,
      ],
    ),
    const EntidadDef(
      tabla: 'eventos_sanitarios', singular: 'Evento sanitario', plural: 'Sanidad',
      descripcion: 'Observación → revisión → diagnóstico profesional → tratamiento autorizado → seguimiento → verificación. Observación ≠ diagnóstico.',
      icono: Icons.medical_services, color: ColoresArea.ganaderia, nivel: 3, campoTitulo: 'descripcion',
      campoEstado: 'etapa', guiaCodigo: 'observacion_sanitaria', orden: 'fecha_hecho',
      transiciones: {
        'observacion': ['revision'],
        'revision': ['diagnostico_profesional', 'seguimiento', 'cerrado'],
        'diagnostico_profesional': ['tratamiento_autorizado', 'seguimiento'],
        'tratamiento_autorizado': ['seguimiento'],
        'seguimiento': ['verificacion'],
        'verificacion': ['cerrado'],
      },
      camposPorEstado: {
        'diagnostico_profesional': ['profesional', 'resultado'],
        'tratamiento_autorizado': ['profesional', 'producto', 'dosis'],
        'verificacion': ['resultado'],
      },
      campos: [
        _animal,
        _lote,
        CampoDef('tipo', 'Tipo', tipo: TipoCampo.opcion, obligatorio: true, enLista: true, opciones: [
          'observacion', 'ectoparasitos', 'endoparasitos', 'vacunacion', 'desparasitacion', 'tratamiento',
          'diagnostico', 'examen', 'control', 'seguimiento'
        ]),
        CampoDef('etapa', 'Etapa', tipo: TipoCampo.opcion, enLista: true, opciones: [
          'observacion', 'revision', 'diagnostico_profesional', 'tratamiento_autorizado', 'seguimiento', 'verificacion', 'cerrado'
        ]),
        _fechaHecho,
        CampoDef('descripcion', 'Qué se observa / qué se hace', tipo: TipoCampo.textoLargo, obligatorio: true),
        CampoDef('producto', 'Producto'),
        CampoDef('dosis', 'Dosis'),
        CampoDef('via', 'Vía'),
        CampoDef('profesional', 'Profesional que diagnostica/autoriza'),
        CampoDef('resultado', 'Resultado', tipo: TipoCampo.textoLargo),
        _naturaleza,
        _calidad,
        _notaCalidad,
      ],
    ),
    const EntidadDef(
      tabla: 'eventos_reproductivos', singular: 'Evento reproductivo', plural: 'Reproducción',
      descripcion: 'Servicio → palpación → diagnóstico de gestación → gestación → parto → destete → secado → producción. No se inventan días entre etapas.',
      icono: Icons.child_friendly, color: ColoresArea.ganaderia, nivel: 3, campoTitulo: 'tipo', orden: 'fecha_hecho',
      campos: [
        CampoDef('animal_id', 'Animal', tipo: TipoCampo.referencia, obligatorio: true, refTabla: 'animales', refEtiqueta: 'numero_interno'),
        CampoDef('tipo', 'Evento', tipo: TipoCampo.opcion, obligatorio: true,
            opciones: ['servicio', 'palpacion', 'diagnostico_gestacion', 'parto', 'destete', 'secado', 'otro']),
        _fechaHecho,
        CampoDef('resultado', 'Resultado', enLista: true, ayuda: 'p. ej. gestante / vacía (lo escribe quien diagnostica)'),
        CampoDef('responsable', 'Responsable'),
        CampoDef('cria_animal_id', 'Cría registrada', tipo: TipoCampo.referencia, refTabla: 'animales', refEtiqueta: 'numero_interno'),
        _naturaleza,
        _descripcion,
        _calidad,
        _notaCalidad,
      ],
    ),
    const EntidadDef(
      tabla: 'produccion_leche', singular: 'Producción de leche', plural: 'Leche',
      descripcion: 'Animal → lactancia → producción → entrega → venta → cuenta por cobrar → pago → ingreso. Entrega ≠ pago.',
      icono: Icons.local_drink, color: ColoresArea.ganaderia, nivel: 3, campoTitulo: 'litros', prefijoTitulo: 'Litros: ',
      orden: 'fecha_hecho',
      campos: [
        _fechaHecho,
        CampoDef('litros', 'Litros', tipo: TipoCampo.decimal, obligatorio: true, unidad: 'L'),
        _animal,
        _lote,
        CampoDef('turno', 'Turno', enLista: true),
        _naturaleza,
        _calidad,
        _notaCalidad,
      ],
    ),
    const EntidadDef(
      tabla: 'entregas_leche', singular: 'Entrega de leche', plural: 'Entregas y pagos de leche',
      descripcion: 'Entregada → vendida → por cobrar → pagada. Una entrega no es un pago.',
      icono: Icons.local_shipping, color: ColoresArea.ganaderia, nivel: 3, campoTitulo: 'litros', prefijoTitulo: 'Litros entregados: ',
      campoEstado: 'estado', orden: 'fecha_hecho',
      transiciones: {
        'entregada': ['vendida', 'por_cobrar', 'pagada', 'rechazada'],
        'vendida': ['por_cobrar', 'pagada'],
        'por_cobrar': ['pagada'],
      },
      camposPorEstado: {'pagada': ['fecha_pago', 'valor_cop']},
      campos: [
        _fechaHecho,
        CampoDef('litros', 'Litros', tipo: TipoCampo.decimal, obligatorio: true, unidad: 'L'),
        CampoDef('comprador', 'Comprador', enLista: true),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, enLista: true,
            opciones: ['entregada', 'vendida', 'por_cobrar', 'pagada', 'rechazada']),
        CampoDef('valor_cop', 'Valor', tipo: TipoCampo.decimal, unidad: 'COP'),
        CampoDef('fecha_pago', 'Fecha de pago', tipo: TipoCampo.fechaHora),
        _naturaleza,
        _descripcion,
      ],
    ),
    const EntidadDef(
      tabla: 'movimientos_economicos', singular: 'Movimiento económico', plural: 'Economía',
      descripcion: 'Costo ≠ gasto ≠ ingreso ≠ pago. La clasificación económica detallada (34.4) sigue en análisis.',
      icono: Icons.payments, color: ColoresArea.general, nivel: 3, campoTitulo: 'concepto', orden: 'fecha_hecho',
      campos: [
        CampoDef('concepto', 'Concepto', obligatorio: true),
        CampoDef('clase', 'Clase', tipo: TipoCampo.opcion, obligatorio: true, enLista: true,
            opciones: ['costo', 'gasto', 'ingreso', 'pago', 'cuenta_por_cobrar', 'cuenta_por_pagar']),
        CampoDef('valor_cop', 'Valor', tipo: TipoCampo.decimal, obligatorio: true, unidad: 'COP', enLista: true),
        _fechaHecho,
        CampoDef('sistema_id', 'Sistema productivo', tipo: TipoCampo.referencia, refTabla: 'sistemas_productivos', refEtiqueta: 'nombre'),
        CampoDef('soporte', 'Soporte (factura/recibo)'),
        _naturaleza,
        _descripcion,
      ],
    ),
    const EntidadDef(
      tabla: 'especies', singular: 'Especie', plural: 'Especies (plantas)',
      descripcion: 'Especie → planta → establecimiento. No se asume que todas se propagan por estaca.',
      icono: Icons.eco, color: ColoresArea.agroecologia, nivel: 3, campoTitulo: 'nombre_comun', orden: 'nombre_comun',
      relaciones: [
        RelacionDef('lotes_vivero', 'especie_id', 'Lotes de vivero'),
        RelacionDef('establecimientos', 'especie_id', 'Establecimientos'),
      ],
      campos: [
        CampoDef('nombre_comun', 'Nombre común', obligatorio: true),
        CampoDef('nombre_cientifico', 'Nombre científico', enLista: true),
        CampoDef('usos', 'Usos'),
        CampoDef('propagacion', 'Formas de propagación conocidas'),
        _descripcion,
      ],
    ),
    const EntidadDef(
      tabla: 'lotes_vivero', singular: 'Lote de vivero', plural: 'Vivero',
      descripcion: 'Especie → origen → lote de vivero → planta → establecimiento → ubicación → seguimiento. Propagación: planta madre → material → nuevo lote.',
      icono: Icons.yard, color: ColoresArea.agroecologia, nivel: 3, campoTitulo: 'codigo', campoEstado: 'estado', orden: 'fecha_inicio',
      transiciones: {
        'en_propagacion': ['listo', 'perdido'],
        'listo': ['trasplantado', 'perdido'],
        'trasplantado': ['cerrado'],
        'perdido': ['cerrado'],
      },
      relaciones: [RelacionDef('establecimientos', 'lote_vivero_id', 'Establecimientos de este lote')],
      campos: [
        CampoDef('codigo', 'Código del lote', obligatorio: true),
        CampoDef('especie_id', 'Especie', tipo: TipoCampo.referencia, obligatorio: true, refTabla: 'especies', refEtiqueta: 'nombre_comun'),
        CampoDef('origen', 'Origen', enLista: true),
        CampoDef('planta_madre', 'Planta madre'),
        CampoDef('metodo_propagacion', 'Método de propagación'),
        CampoDef('fecha_inicio', 'Fecha de inicio', tipo: TipoCampo.fechaHora, obligatorio: true),
        CampoDef('cantidad_inicial', 'Cantidad inicial', tipo: TipoCampo.entero),
        CampoDef('cantidad_actual', 'Cantidad actual', tipo: TipoCampo.entero, enLista: true),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, enLista: true,
            opciones: ['en_propagacion', 'listo', 'trasplantado', 'perdido', 'cerrado']),
        _unidad,
        _naturaleza,
        _descripcion,
      ],
    ),
    const EntidadDef(
      tabla: 'establecimientos', singular: 'Establecimiento de plantas', plural: 'Plantas establecidas',
      descripcion: 'Establecimiento → edad calculada → etapa → condición observada → criterio → revisión → actividad → seguimiento. No se inventan edades ni frecuencias.',
      icono: Icons.forest, color: ColoresArea.agroecologia, nivel: 3, campoTitulo: 'etapa', campoEstado: 'etapa', orden: 'fecha_hecho',
      transiciones: {
        'siembra': ['establecimiento', 'perdido'],
        'establecimiento': ['crecimiento', 'perdido', 'reemplazado'],
        'crecimiento': ['produccion', 'mantenimiento', 'perdido', 'reemplazado'],
        'produccion': ['mantenimiento', 'reemplazado'],
        'mantenimiento': ['produccion', 'crecimiento'],
      },
      campos: [
        CampoDef('especie_id', 'Especie', tipo: TipoCampo.referencia, obligatorio: true, refTabla: 'especies', refEtiqueta: 'nombre_comun'),
        CampoDef('lote_vivero_id', 'Lote de vivero', tipo: TipoCampo.referencia, refTabla: 'lotes_vivero', refEtiqueta: 'codigo'),
        CampoDef('sistema_id', 'Sistema (silvopastoril, pancoger…)', tipo: TipoCampo.referencia, refTabla: 'sistemas_productivos', refEtiqueta: 'nombre'),
        _unidad,
        _fechaHecho,
        CampoDef('cantidad', 'Cantidad', tipo: TipoCampo.entero, enLista: true),
        CampoDef('etapa', 'Etapa', tipo: TipoCampo.opcion, enLista: true, opciones: [
          'siembra', 'establecimiento', 'crecimiento', 'produccion', 'mantenimiento', 'perdido', 'reemplazado'
        ]),
        CampoDef('condicion', 'Condición observada'),
        CampoDef('sobrevivencia', 'Plantas vivas (conteo)', tipo: TipoCampo.entero),
        _naturaleza,
        _descripcion,
      ],
    ),
    // ── NIVEL 4: PROCESOS Y ACTIVIDADES ────────────────────────────────────
    const EntidadDef(
      tabla: 'actividades', singular: 'Actividad', plural: 'Actividades y tareas',
      descripcion: 'Programada → iniciada → ejecutada → requiere verificación → verificada → cerrada. Ejecutada ≠ verificada ≠ cerrada. Muchas se crean solas desde los procesos (pastoreo, aforo, sanidad, reproducción, suelo, infraestructura, decisiones, alertas).',
      icono: Icons.task_alt, color: ColoresArea.general, nivel: 4, campoTitulo: 'titulo', campoEstado: 'estado',
      orden: 'created_at', transiciones: _estadosActividad,
      camposPorEstado: {
        'ejecutada': ['resultado'],
        'verificada': ['verificacion'],
        'bloqueada': ['nota_estado'],
        'reprogramada': ['nota_estado', 'fecha_programada'],
        'cancelada': ['nota_estado'],
        'parcial': ['nota_estado', 'resultado'],
        'no_aplica': ['nota_estado'],
        'programada': ['fecha_programada'],
      },
      campos: [
        CampoDef('titulo', 'Título', obligatorio: true),
        CampoDef('tipo', 'Tipo', tipo: TipoCampo.opcion, opciones: ['actividad', 'tarea', 'seguimiento', 'verificacion']),
        CampoDef('proceso', 'Proceso', enLista: true, ayuda: 'pastoreo, sanidad, mantenimiento…'),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, soloLectura: true, enLista: true, opciones: [
          'programada', 'pendiente', 'disponible', 'iniciada', 'pausada', 'reanudada', 'requiere_verificacion',
          'verificada', 'cerrada', 'bloqueada', 'parcial', 'reprogramada', 'cancelada', 'no_aplica'
        ]),
        CampoDef('fecha_programada', 'Fecha programada', tipo: TipoCampo.fechaHora, enLista: true,
            ayuda: 'Vacía = pendiente sin fecha (no se inventa)'),
        CampoDef('responsable', 'Responsable'),
        CampoDef('verificador', 'Verificador'),
        _animal,
        _lote,
        _unidad,
        _descripcion,
        CampoDef('requiere_seguimiento', 'Al verificar, crear seguimiento', tipo: TipoCampo.booleano),
        CampoDef('resultado', 'Resultado (qué se hizo)', tipo: TipoCampo.textoLargo, enFormulario: false),
        CampoDef('verificacion', 'Cómo se verificó', tipo: TipoCampo.textoLargo, enFormulario: false),
        CampoDef('nota_estado', 'Motivo del estado', tipo: TipoCampo.textoLargo, enFormulario: false),
        CampoDef('origen_tipo', 'Origen', soloLectura: true, enFormulario: false),
        CampoDef('fecha_ejecucion', 'Ejecutada el', tipo: TipoCampo.fechaHora, soloLectura: true, enFormulario: false),
        CampoDef('fecha_verificacion', 'Verificada el', tipo: TipoCampo.fechaHora, soloLectura: true, enFormulario: false),
        CampoDef('guia_codigo', 'Guía', soloLectura: true, enFormulario: false),
        _objetoTipo,
        _objetoId,
      ],
    ),
    // ── NIVEL 5: MONITOREO ─────────────────────────────────────────────────
    const EntidadDef(
      tabla: 'alertas', singular: 'Alerta', plural: 'Alertas',
      descripcion: 'Una alerta indica que algo requiere revisión. No demuestra la causa; cerrarla no resuelve la causa. Se puede convertir en actividad, decisión o hallazgo.',
      icono: Icons.warning_amber, color: ColoresArea.general, nivel: 5, campoTitulo: 'mensaje', campoEstado: 'estado',
      transiciones: {
        'generada': ['revisada', 'en_analisis', 'descartada', 'cerrada'],
        'pendiente': ['revisada', 'en_analisis', 'descartada', 'cerrada'],
        'revisada': ['en_analisis', 'atendida', 'descartada', 'cerrada'],
        'en_analisis': ['atendida', 'descartada', 'cerrada'],
        'atendida': ['cerrada'],
        'descartada': ['cerrada'],
      },
      camposPorEstado: {'descartada': ['nota'], 'atendida': ['nota']},
      campos: [
        CampoDef('mensaje', 'Mensaje', obligatorio: true),
        CampoDef('tipo', 'Tipo', enLista: true),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, soloLectura: true, enLista: true, opciones: [
          'generada', 'pendiente', 'revisada', 'en_analisis', 'atendida', 'descartada', 'convertida_actividad',
          'convertida_decision', 'convertida_hallazgo', 'cerrada'
        ]),
        CampoDef('regla', 'Regla que la generó', soloLectura: true),
        CampoDef('nota', 'Nota', tipo: TipoCampo.textoLargo),
        _objetoTipo,
        _objetoId,
        CampoDef('clave', 'Clave', soloLectura: true, enFormulario: false),
      ],
    ),
    const EntidadDef(
      tabla: 'observaciones', singular: 'Observación', plural: 'Observaciones',
      descripcion: 'Lo que alguien vio, vinculado al objeto observado. Observación ≠ medición ≠ diagnóstico.',
      icono: Icons.visibility, color: ColoresArea.general, nivel: 5, campoTitulo: 'texto', orden: 'fecha_hecho',
      campos: [
        CampoDef('texto', 'Qué se observó', tipo: TipoCampo.textoLargo, obligatorio: true),
        CampoDef('fecha_hecho', 'Fecha del hecho', tipo: TipoCampo.fechaHora, obligatorio: true),
        _naturaleza,
        _objetoTipo,
        _objetoId,
      ],
    ),
    // ── NIVEL 6: ANÁLISIS ──────────────────────────────────────────────────
    const EntidadDef(
      tabla: 'hallazgos', singular: 'Análisis', plural: 'Señales, hallazgos, hipótesis y diagnósticos',
      descripcion: 'Señal = requiere revisión; hallazgo = resultado de análisis; hipótesis = explicación no confirmada; diagnóstico = conclusión con fundamento y, si corresponde, validación profesional. Correlación ≠ causalidad.',
      icono: Icons.insights, color: ColoresArea.general, nivel: 6, campoTitulo: 'titulo', campoEstado: 'estado',
      transiciones: {
        'preliminar': ['en_revision', 'validado', 'descartado'],
        'en_revision': ['validado', 'descartado', 'reemplazado'],
        'validado': ['reemplazado'],
      },
      camposPorEstado: {'validado': ['validado_por']},
      campos: [
        CampoDef('titulo', 'Título', obligatorio: true),
        CampoDef('tipo', 'Tipo', tipo: TipoCampo.opcion, obligatorio: true, enLista: true,
            opciones: ['senal', 'hallazgo', 'hipotesis', 'diagnostico']),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, soloLectura: true, enLista: true,
            opciones: ['preliminar', 'en_revision', 'validado', 'descartado', 'reemplazado']),
        CampoDef('descripcion', 'Descripción', tipo: TipoCampo.textoLargo),
        CampoDef('datos_usados', 'Datos usados', tipo: TipoCampo.textoLargo),
        CampoDef('metodo', 'Método'),
        CampoDef('incertidumbre', 'Incertidumbre', tipo: TipoCampo.textoLargo),
        CampoDef('validado_por', 'Validado por (profesional si es diagnóstico)'),
        _objetoTipo,
        _objetoId,
      ],
    ),
    // ── NIVEL 7: DECISIONES ────────────────────────────────────────────────
    const EntidadDef(
      tabla: 'recomendaciones', singular: 'Recomendación', plural: 'Recomendaciones',
      descripcion: 'Una recomendación es una propuesta, no una decisión. Generada → revisión → aceptada / modificada / rechazada / reemplazada.',
      icono: Icons.lightbulb, color: ColoresArea.general, nivel: 7, campoTitulo: 'titulo', campoEstado: 'estado',
      transiciones: {
        'generada': ['revision', 'aceptada', 'modificada', 'rechazada'],
        'revision': ['aceptada', 'modificada', 'rechazada', 'reemplazada'],
        'modificada': ['revision', 'aceptada', 'rechazada'],
      },
      camposPorEstado: {'rechazada': ['nota_revision'], 'modificada': ['nota_revision'], 'reemplazada': ['nota_revision']},
      relaciones: [
        RelacionDef('alternativas', 'recomendacion_id', 'Alternativas (sin ranking arbitrario)'),
        RelacionDef('decisiones', 'recomendacion_id', 'Decisiones tomadas'),
      ],
      campos: [
        CampoDef('titulo', 'Título', obligatorio: true),
        CampoDef('origen', 'Origen', tipo: TipoCampo.opcion, enLista: true, opciones: ['humano', 'ia', 'regla']),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, soloLectura: true, enLista: true,
            opciones: ['generada', 'revision', 'aceptada', 'modificada', 'rechazada', 'reemplazada']),
        CampoDef('descripcion', 'Descripción', tipo: TipoCampo.textoLargo),
        CampoDef('hallazgo_id', 'Hallazgo de origen', tipo: TipoCampo.referencia, refTabla: 'hallazgos', refEtiqueta: 'titulo'),
        CampoDef('datos_usados', 'Datos usados', tipo: TipoCampo.textoLargo),
        CampoDef('metodo', 'Método'),
        CampoDef('criterio', 'Criterio'),
        CampoDef('criterio_version', 'Versión del criterio'),
        CampoDef('fuente', 'Fuente'),
        CampoDef('incertidumbre', 'Incertidumbre', tipo: TipoCampo.textoLargo),
        CampoDef('nota_revision', 'Nota de revisión', tipo: TipoCampo.textoLargo),
      ],
    ),
    const EntidadDef(
      tabla: 'alternativas', singular: 'Alternativa', plural: 'Alternativas',
      icono: Icons.alt_route, color: ColoresArea.general, nivel: 7, campoTitulo: 'descripcion',
      campos: [
        CampoDef('recomendacion_id', 'Recomendación', tipo: TipoCampo.referencia, obligatorio: true, refTabla: 'recomendaciones', refEtiqueta: 'titulo'),
        CampoDef('descripcion', 'Alternativa', tipo: TipoCampo.textoLargo, obligatorio: true),
        CampoDef('condiciones', 'Condiciones', tipo: TipoCampo.textoLargo),
        CampoDef('ventajas', 'Ventajas', tipo: TipoCampo.textoLargo),
        CampoDef('desventajas', 'Desventajas', tipo: TipoCampo.textoLargo),
        CampoDef('recursos', 'Recursos necesarios', tipo: TipoCampo.textoLargo),
      ],
    ),
    const EntidadDef(
      tabla: 'decisiones', singular: 'Decisión', plural: 'Decisiones',
      descripcion: 'Borrador → revisión → aprobada → programada → ejecutándose → cumplida → verificada → cerrada. Al aprobar se exige: datos usados, método, criterio y su versión, fuente y evidencia (§33). La actividad se programa sola y la decisión avanza con ella.',
      icono: Icons.gavel, color: ColoresArea.general, nivel: 7, campoTitulo: 'titulo', campoEstado: 'estado',
      transiciones: {
        'borrador': ['revision', 'aprobada'],
        'revision': ['borrador', 'aprobada'],
        'aprobada': ['programada', 'ejecutandose', 'cumplida'],
        'programada': ['ejecutandose', 'cumplida'],
        'ejecutandose': ['cumplida'],
        'cumplida': ['verificada'],
        'verificada': ['cerrada'],
      },
      camposPorEstado: {
        'aprobada': ['datos_usados', 'metodo', 'criterio', 'criterio_version', 'fuente', 'evidencia'],
        'cumplida': ['resultado'],
        'verificada': ['verificacion'],
      },
      relaciones: [RelacionDef('actividades', 'origen_id', 'Actividades de esta decisión')],
      campos: [
        CampoDef('titulo', 'Título', obligatorio: true),
        CampoDef('resolucion', 'Resolución', tipo: TipoCampo.opcion, enLista: true, opciones: [
          'aceptar', 'rechazar', 'modificar', 'posponer', 'solicitar_informacion', 'seleccionar_alternativa', 'no_intervencion', 'otra'
        ]),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, soloLectura: true, enLista: true, opciones: [
          'borrador', 'revision', 'aprobada', 'programada', 'ejecutandose', 'cumplida', 'verificada', 'cerrada'
        ]),
        CampoDef('descripcion', 'Descripción', tipo: TipoCampo.textoLargo),
        CampoDef('recomendacion_id', 'Recomendación', tipo: TipoCampo.referencia, refTabla: 'recomendaciones', refEtiqueta: 'titulo'),
        CampoDef('alternativa_id', 'Alternativa elegida', tipo: TipoCampo.referencia, refTabla: 'alternativas', refEtiqueta: 'descripcion'),
        CampoDef('hallazgo_id', 'Hallazgo', tipo: TipoCampo.referencia, refTabla: 'hallazgos', refEtiqueta: 'titulo'),
        CampoDef('datos_usados', 'Datos usados', tipo: TipoCampo.textoLargo),
        CampoDef('metodo', 'Método'),
        CampoDef('criterio', 'Criterio'),
        CampoDef('criterio_version', 'Versión del criterio'),
        CampoDef('fuente', 'Fuente'),
        CampoDef('evidencia', 'Evidencia'),
        CampoDef('condicion', 'Condición (si es decisión condicional)', tipo: TipoCampo.textoLargo,
            ayuda: 'No se ejecutan acciones sensibles hasta comprobarla'),
        CampoDef('accion_titulo', 'Actividad a programar al aprobar'),
        CampoDef('accion_fecha', 'Fecha de la actividad', tipo: TipoCampo.fechaHora),
        CampoDef('accion_responsable', 'Responsable de la actividad'),
        CampoDef('resultado', 'Resultado', tipo: TipoCampo.textoLargo, enFormulario: false),
        CampoDef('verificacion', 'Verificación', tipo: TipoCampo.textoLargo, enFormulario: false),
        CampoDef('aprobada_en', 'Aprobada el', tipo: TipoCampo.fechaHora, soloLectura: true, enFormulario: false),
      ],
    ),
    // ── NIVEL 8: MEJORA CONTINUA ───────────────────────────────────────────
    const EntidadDef(
      tabla: 'aprendizajes', singular: 'Aprendizaje', plural: 'Aprendizajes y mejoras',
      descripcion: 'Experiencia → evaluación → aprendizaje → propuesta de mejora → revisión → aprobación → implementación → nueva versión → validación → conocimiento. No todo evento se vuelve regla.',
      icono: Icons.school, color: ColoresArea.general, nivel: 8, campoTitulo: 'titulo', campoEstado: 'estado',
      transiciones: {
        'experiencia': ['evaluacion', 'descartada'],
        'evaluacion': ['aprendizaje', 'descartada'],
        'aprendizaje': ['propuesta', 'conocimiento', 'descartada'],
        'propuesta': ['revision'],
        'revision': ['aprobada', 'descartada'],
        'aprobada': ['implementada'],
        'implementada': ['nueva_version'],
        'nueva_version': ['validada'],
        'validada': ['conocimiento'],
      },
      camposPorEstado: {
        'evaluacion': ['evaluacion'],
        'aprendizaje': ['aprendizaje'],
        'propuesta': ['propuesta_mejora'],
        'implementada': ['implementacion'],
        'validada': ['validacion'],
      },
      campos: [
        CampoDef('titulo', 'Título', obligatorio: true),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, soloLectura: true, enLista: true, opciones: [
          'experiencia', 'evaluacion', 'aprendizaje', 'propuesta', 'revision', 'aprobada', 'implementada',
          'nueva_version', 'validada', 'conocimiento', 'descartada'
        ]),
        CampoDef('experiencia', 'Experiencia (qué pasó)', tipo: TipoCampo.textoLargo),
        CampoDef('evaluacion', 'Evaluación', tipo: TipoCampo.textoLargo),
        CampoDef('aprendizaje', 'Aprendizaje', tipo: TipoCampo.textoLargo),
        CampoDef('propuesta_mejora', 'Propuesta de mejora', tipo: TipoCampo.textoLargo),
        CampoDef('implementacion', 'Implementación', tipo: TipoCampo.textoLargo),
        CampoDef('validacion', 'Validación', tipo: TipoCampo.textoLargo),
      ],
    ),
    const EntidadDef(
      tabla: 'incidentes_tecnicos', singular: 'Incidencia técnica', plural: 'Incidencias técnicas de la app',
      descripcion: 'Reportado → diagnóstico → solución propuesta → intervención requerida → corrigiendo → pruebas → resuelto → verificado → cerrado. Causa confirmada ≠ hipótesis.',
      icono: Icons.bug_report, color: ColoresArea.general, nivel: 8, campoTitulo: 'titulo', campoEstado: 'estado',
      tieneMotivoAnulacion: false,
      transiciones: {
        'reportado': ['diagnostico'],
        'abierto': ['diagnostico', 'en_analisis'],
        'diagnostico': ['solucion_propuesta', 'intervencion_requerida'],
        'en_analisis': ['solucion_propuesta', 'resuelto'],
        'solucion_propuesta': ['corrigiendo', 'intervencion_requerida'],
        'intervencion_requerida': ['corrigiendo'],
        'corrigiendo': ['pruebas'],
        'pruebas': ['resuelto', 'corrigiendo'],
        'resuelto': ['verificado', 'cerrado'],
        'verificado': ['cerrado'],
      },
      camposPorEstado: {'resuelto': ['resolucion'], 'cerrado': ['resolucion']},
      campos: [
        CampoDef('titulo', 'Qué pasó', obligatorio: true),
        CampoDef('tipo', 'Tipo', tipo: TipoCampo.opcion, obligatorio: true, enLista: true,
            opciones: ['sincronizacion', 'datos', 'sistema', 'seguridad', 'otro']),
        CampoDef('severidad', 'Severidad', tipo: TipoCampo.opcion, enLista: true, opciones: ['baja', 'media', 'alta']),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, soloLectura: true, enLista: true, opciones: [
          'reportado', 'abierto', 'diagnostico', 'en_analisis', 'solucion_propuesta', 'intervencion_requerida',
          'corrigiendo', 'pruebas', 'resuelto', 'verificado', 'cerrado'
        ]),
        CampoDef('descripcion', 'Descripción', tipo: TipoCampo.textoLargo),
        CampoDef('modulo', 'Módulo'),
        CampoDef('pantalla', 'Pantalla'),
        CampoDef('version_app', 'Versión de la app', soloLectura: true),
        CampoDef('conectividad', 'Conectividad'),
        CampoDef('resolucion', 'Resolución', tipo: TipoCampo.textoLargo, enFormulario: false),
      ],
    ),
    // ── TRANSVERSALES ──────────────────────────────────────────────────────
    const EntidadDef(
      tabla: 'evidencias', singular: 'Evidencia', plural: 'Evidencias y documentos',
      descripcion: 'Fotos, PDF y documentos van a Google Drive; aquí queda el registro y el enlace. El registro respalda el hecho; la evidencia no es validación.',
      icono: Icons.attach_file, color: ColoresArea.general, nivel: 5, campoTitulo: 'descripcion', campoEstado: 'estado',
      transiciones: {'pendiente_sincronizacion': ['subida', 'error'], 'error': ['subida']},
      camposPorEstado: {'subida': ['enlace']},
      campos: [
        CampoDef('descripcion', 'Descripción', obligatorio: true),
        CampoDef('tipo', 'Tipo', tipo: TipoCampo.opcion, obligatorio: true, enLista: true,
            opciones: ['foto', 'pdf', 'documento', 'informe_laboratorio', 'factura', 'otro']),
        CampoDef('enlace', 'Enlace de Google Drive', ayuda: 'Pegue el enlace del archivo en Drive'),
        CampoDef('estado', 'Estado', tipo: TipoCampo.opcion, soloLectura: true, enLista: true,
            opciones: ['pendiente_sincronizacion', 'subida', 'error']),
        CampoDef('fecha_hecho', 'Fecha del hecho', tipo: TipoCampo.fechaHora),
        _objetoTipo,
        _objetoId,
      ],
    ),
    const EntidadDef(
      tabla: 'destinos_superficie', singular: 'Superficie por destino', plural: 'Superficies por destino',
      descripcion: 'Cuántas hectáreas se destinan a cada área. Toda superficie declara su naturaleza (estimada, medida, calculada…).',
      icono: Icons.square_foot, color: ColoresArea.agroecologia, nivel: 1, campoTitulo: 'destino', orden: 'destino',
      tieneMotivoAnulacion: false,
      campos: [
        CampoDef('destino', 'Destino', obligatorio: true),
        CampoDef('superficie_ha', 'Superficie', tipo: TipoCampo.decimal, obligatorio: true, unidad: 'ha', enLista: true),
        _naturaleza,
        CampoDef('observaciones', 'Observaciones', tipo: TipoCampo.textoLargo),
      ],
    ),
  ])
    d.tabla: d,
};

/// Ruta de navegación para abrir un objeto por su tabla.
String rutaObjeto(String? tabla, String? id) {
  if (tabla == null || id == null) return '/';
  switch (tabla) {
    case 'animales':
      return '/animales/$id';
    case 'aforos':
      return '/aforo/$id';
    case 'lotes_ganaderos':
      return '/lotes';
    case 'unidades_espaciales':
    case 'ocupaciones_pastoreo':
      return '/potreros';
    case 'guias':
      return '/guias/$id';
    case 'pesajes':
    case 'qr_operaciones':
      return '/qr';
  }
  if (catalogo.containsKey(tabla)) return '/e/$tabla/$id';
  return '/';
}
