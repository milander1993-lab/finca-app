# DOCUMENTO MAESTRO V5 — Sistema Agroecológico Integral para Finca
Fecha: 30-sep-2026 · Sustituye a V4 como fuente de verdad operativa. V4 (decisiones D-001–D-026, CHG-001–008, DT-001–007) sigue vigente salvo lo que aquí se indique.

---
## 0. Cómo leer este documento
1. **Estado real** (qué está hecho y con qué nivel de verificación): sección 1.
2. **Decisiones nuevas** desde V4: sección 2.
3. **Bloque 34.2 — Arquitectura de rendimiento, escalabilidad y capacidad** (el siguiente bloque que marcaba el punto de continuidad 34.23): sección 3. Es una **propuesta en estado "Validación pendiente"**: los números son propuestas, no objetivos aprobados.
4. **Ruta hasta la app completa**, fase por fase, con lo que cada una necesita de ti: sección 4.
5. **Prompt de continuidad** para pegar en una conversación nueva: sección 6.

---
## 1. Estado real y nivel de verificación

| Entregable | Qué es | Verificación |
|---|---|---|
| `00002_iteracion1_integridad_qr_pesajes.sql` | Triggers de timestamps/autoría/auditoría, auditoría append-only, máquina de estados del QR en la BD, bandeja `qr_operaciones` (asignar/confirmar/liberar/habilitar/registrar con conflicto), `pesajes` con naturaleza, `peso_ultimo` derivado, pertenencia a finca (`finca_miembros`) y RLS | **Ejecutada y probada en Postgres 16 + PostGIS** |
| `00003_mapa_geometrias.sql` | Geometría válida/4326 con naturaleza obligatoria, vista `v_unidades_mapa` (GeoJSON + área calculada) | **Ejecutada y probada** |
| `00004_lotes_animal_lote.sql` | `lotes_ganaderos` (solo si no existe) y `animal_lote` histórica, 1 lote abierto por animal | **Ejecutada y probada** |
| `00005_evidencias_animal.sql` | Evidencia fotográfica (D-006/D-008/DT-006): tipos aprobados, una principal vigente, cola de subida a Drive, archivo subido inmutable. Ángulos/zonas como texto libre hasta la guía 34.9 | **Ejecutada y probada** |
| `00006_guias_tecnicas.sql` | Estructura de guías versionadas con los 16 elementos de la regla de oro: sin contenido, no se publica incompleta (exige los 16 + fuente + revisor), lo publicado no se edita, corregir = versión nueva | **Ejecutada y probada** |
| `00007_pasturas_rotacion.sql` | Máx. 6 potreros principales; divisiones temporales (A1, A2…) con nombre libre y único que nunca se vuelven permanentes; superficie en ha por unidad y por destino (vacío = sin datos); ocupación lote↔área sin solapamientos; **alerta si pasa de 2 días** (sin inventar causa); estructura de aforo con %MS calculado o "no calculable" | **Ejecutada y probada** |
| Pruebas SQL (`supabase/tests/`) | Corrida integral desde base limpia de 00002–00007: 111 comprobaciones (60 avisos OK, 33 tablas ok, 18 operaciones QR), **0 fallas** | Ejecutadas |
| Módulo Flutter QR (`lib/features/qr`) | Estados, validaciones locales, repositorio con cola, providers, pantalla de escaneo | **SIN COMPILAR** (no hay Dart/Flutter en el entorno) |
| Módulo Flutter mapa (`lib/features/mapa`) | Parser GeoJSON, pantalla flutter_map con "sin datos" | **SIN COMPILAR** |
| Pruebas Dart (`test/`) | 9 pruebas unitarias | **Escritas, nunca ejecutadas** |

**Límites honestos**
- La base se probó contra una **reconstrucción** de tu 00001 y un **simulacro** de Supabase (roles y `auth.uid()`), no contra tu proyecto real. Hay que correr 00002→00004 en tu Supabase real (primero en un proyecto de prueba).
- Tus archivos Flutter reales nunca llegaron. Los módulos Dart se conectan por interfaces (`QrFuenteDatos`) que debe implementar tu capa Drift/PowerSync.
- No hay credenciales (Supabase, PowerSync, Google Drive). Nada de eso se simuló como si existiera.

---
## 2. Decisiones nuevas (modo automático)

| ID | Decisión | Por qué / alcance |
|---|---|---|
| DT-008 | Pertenencia a finca sin roles (`finca_miembros`); permisos granulares esperan 34.3 | No se inventan personas ni roles |
| DT-009 | QR `asignado` = vinculado en sistema, chapa sin confirmar; `activo` = confirmado en campo | Interpretación de DA-007. **Corregible por ti** |
| DT-010 | Capa de datos del cliente como interfaces hasta recibir los archivos reales | No se reconstruye lo que ya existe |
| DT-011 | `lotes_ganaderos` se crea solo si no existe (mínimo: id, finca_id, nombre, estado) | Cierra parcialmente CHG-008; revisar contra tu base |
| DT-012 | Las reglas críticas viven en la BD (triggers), no solo en la app | Ningún cliente, viejo o nuevo, puede saltarlas |
| DT-013 | Operaciones offline críticas = "solicitud con id de cliente" + resultado del servidor (`aplicada/rechazada/conflicto`) | Cumple D-026: sin "última escritura gana" |
| DT-014 | Geometría sin dato = "sin datos"; toda geometría exige naturaleza declarada | Cumple "no inventar datos" y DA-025 |
| DT-015 | La app nunca afirma éxito de una operación QR hasta que el servidor responde | Coherencia offline/online |

Ninguna decisión aprobada fue modificada. No se detectaron contradicciones nuevas.

---
### 2.1 Decisiones del 30-sep 21:40 (reglas ya aprobadas, ahora implementadas) y corrección de conducta
| ID | Decisión |
|---|---|
| DT-016 | Los **valores** de la finca (cuántos animales, pesos, hectáreas, coordenadas) los ingresa el usuario desde la app cuando quiera. **No son requisito para construir.** La app debe aceptar 1, 2 o 1000 animales sin cambios |
| DT-017 | La app debe abrirse en cualquier teléfono o navegador (PWA / Flutter web, CHG-002). El modelo de teléfono no condiciona el diseño |
| DT-018 | Convención: `unidades_espaciales.tipo` = `potrero` (máx. 6, permanente) o `division` (temporal, A1, A2…). Ocupación máxima 48 h por defecto (D-012), función `ocupacion_max_horas()` |
| DT-019 | Costo máximo aceptado: **50 000 COP/mes**. Almacenamiento de evidencias: Google Drive (5 TB, Google One). Primero planes gratuitos; ver sección 3.9 |
**Corrección de conducta:** no se piden datos que la app captura después ni se propone reemplazar la app por una hoja de cálculo; eso contradice decisiones cerradas. Solo se pregunta por lo que bloquea técnicamente (archivos Flutter, credenciales) o por contradicciones reales.

## 2.2 Datos reales declarados por el usuario (30-sep-2026 22:01)
Datos **declarados**, no medidos ni verificados. El usuario los ingresa en la app cuando quiera; aquí solo orientan el dimensionamiento.
| Dato | Valor declarado | Nota |
|---|---|---|
| Hato actual | 3 vacas, 2 terneras, 1 ternero (6 animales) | La categoría D-013 (terneros, levante, novillas, vacas, toros) es independiente del sexo |
| Crecimiento esperado | 50 a máximo 100 animales en 10 años | Sirve para dimensionar; no es límite del sistema |
| Usuarios | Hoy 2 (administrador + 1 colaborador). A futuro máximo 3 empleos directos, según recursos y crecimiento | Roles reales siguen pendientes (34.3) |
| Superficie total | 33 ha | |
| Pancoger | 4 ha | |
| Banco de forraje mixto para ensilaje | 4 ha (a futuro) | Estado: proyectado |
| Bosque | ≈ 4 ha | Aproximado. Conservación **sin afirmar protección legal** |
| Humedal | ≈ 1 ha, alargado (largo, no ancho) | Aproximado. Forma lineal: la geometría real definirá el área |
| Ganadería (producción) | ≈ 20 ha (33 − 13, **calculado por resta**) | Destino declarado por el usuario. Como bosque y humedal son aproximados, esta cifra también lo es. Distribución en los 6 potreros: pendiente de levantamiento |
**Consecuencias para el dimensionamiento:** hasta 100 animales y 3–5 usuarios caben con holgura en los planes gratuitos de Supabase (500 MB) y PowerSync (2 GB/mes, 50 clientes simultáneos); el único riesgo es la pausa por una semana sin actividad (ver 3.9).

---
## 3. Bloque 34.2 — Arquitectura de rendimiento, escalabilidad y capacidad
**Estado: Validación pendiente (propuesta completa, sin objetivos numéricos aprobados).**
Es el bloque que 34.23 fijaba como siguiente. Lo dejo definido para que lo apruebes o corrijas.

### 3.1 Principio rector
Todo lo que el usuario hace en el potrero debe sentirse instantáneo **sin internet**. La red es un detalle de sincronización, nunca de la interacción.

### 3.2 Operaciones críticas (las que no pueden sentirse lentas)
1. Escanear QR y ver el animal.
2. Registrar un peso, sanidad, o un evento de pastoreo.
3. Abrir el mapa con potreros.
4. Buscar un animal por número interno.
5. Ver el resumen de un lote/potrero.

### 3.3 Mecanismos (ya reflejados en el esquema/código)
| Mecanismo | Dónde |
|---|---|
| Escritura local primero (SQLite/Drift), sincronización en segundo plano | Cliente (DT-003/004/013) |
| Índices para búsquedas por finca, categoría, estado, QR, pesaje reciente | 00002 (sección 7.4) |
| Un solo lote/QR abierto por animal con índice parcial (consulta O(1)) | 00002, 00004 |
| Valores derivados (peso_ultimo) mantenidos por trigger, no recalculados en cada consulta | 00002 |
| Geometrías: GIST en servidor, GeoJSON texto en el dispositivo, dibujar solo lo visible | 00003 |
| Auditoría append-only separada, leída bajo demanda, no sincronizada al cliente por defecto | 00002 |
| Fotos/PDF fuera de la BD (Google Drive, D-008), subida por cola en segundo plano con miniaturas | Pendiente Iter. evidencia |
| Paginación y carga diferida en listas; cálculos pesados en isolates | Cliente |

### 3.4 Objetivos numéricos — PROPUESTA, NO APROBADOS
| Medida | Propuesta |
|---|---|
| Escaneo QR → ficha visible (offline) | ≤ 1 s |
| Guardar un registro (confirmación local) | ≤ 300 ms |
| Abrir mapa con ≤ 50 polígonos | ≤ 2 s |
| Búsqueda de animal por número | ≤ 500 ms |
| Sincronización de una operación con señal normal | ≤ 10 s |
| Volumen de diseño | 1 finca, cientos de animales, decenas de unidades espaciales, miles de pesajes/año |
Justificación: son umbrales de "se siente fluido" habituales, **no medidos en tu finca ni en tu dispositivo**. Hay que medirlos en un teléfono real de gama media que uses tú.

### 3.5 Escalabilidad
La arquitectura (todo por `finca_id`, RLS por finca, índices por finca) permite varias fincas sin rediseñar. No se diseña para miles de fincas: **no corresponde** (evitar sobreingeniería).

### 3.6 Capacidad y almacenamiento
- Datos estructurados: muy pequeños para el volumen esperado.
- Lo que crece es **fotografía/evidencia** (D-008, 34.9): se controla con compresión, miniaturas, y política de retención (pendiente 34.20).
- Auditoría: crece linealmente; se archiva por periodo (política pendiente 34.12/34.20).

### 3.7 Pruebas de rendimiento (a ejecutar cuando exista la app real)
1. Carga sintética: 1 000 animales, 10 000 pesajes, 100 polígonos.
2. Cronometrar las 5 operaciones críticas en el teléfono real, modo avión y con red lenta.
3. Medir sincronización tras 1 h sin conexión con 200 operaciones en cola.
4. Criterio de aceptación: cumplir 3.4 o ajustar los números con tu aprobación.

### 3.9 Costos (verificado el 30-sep-2026 en las páginas oficiales)
| Servicio | Gratis | De pago | Consecuencia |
|---|---|---|---|
| Supabase | 500 MB de base de datos; el proyecto se **pausa tras 1 semana sin actividad** | Pro 25 USD/mes (copias diarias, 8 GB) | Gratis alcanza para datos estructurados (las fotos van a Drive). Pro probablemente supera los 50 000 COP |
| PowerSync | 2 GB sincronizados/mes, 50 clientes, **se desactiva tras 1 semana sin actividad** | Pro desde 49 USD/mes | Gratis alcanza para una finca. Pro supera el presupuesto |
| Google Drive | Ya cubierto por tu Google One | — | Sin costo adicional |
Plan: arrancar en gratis; con uso diario no se pausan. Sin copias automáticas en el plan gratis, por lo que se agrega una exportación periódica a tu Drive (pendiente de implementar). Si algún día se supera el límite, se evalúa pasar a pago o simplificar la sincronización.

### 3.8 Qué queda abierto en 34.2
Aprobar o cambiar los números de 3.4; conocer el teléfono real de uso; medir conectividad real en la finca.

---
## 4. Ruta hasta la app completa (fases y qué las bloquea)
Regla: no se adelanta ninguna fase cuyo dato real o decisión no exista (prioridad 4 del proyecto).

| Fase | Contenido | Estado | Qué necesita de ti |
|---|---|---|---|
| Iter. 1 | Territorio + QR + pesajes + mapa + lotes (base de datos) | **Hecha y probada en BD** · Dart sin compilar | Correrla en tu Supabase; entregar archivos Flutter reales |
| Iter. 1b | Conexión Flutter (Drift/PowerSync/go_router) | Bloqueada | Archivos reales + credenciales Supabase/PowerSync |
| Iter. 2 | Ganadería base: ficha animal, fotos principal/corporal, eventos de vida | **Parcial: evidencias (00005) hecha.** Faltan eventos de vida y restricción de `categoria` (D-013: terneros, levante, novillas, vacas, toros) | Cómo guarda hoy tu cliente `categoria` (singular/plural) para poder restringirla sin romper nada; lista de tipos de evento de vida; guía fotográfica (34.9) |
| Iter. 3 | Pastoreo: aforo → MS → demanda → rotación (DA-047) | **Parcial: 00007 hecha** (potreros, divisiones, ocupación, alerta 2 días, aforo, %MS). Falta demanda de MS y plan de aforo | Parámetro de % de consumo (referencia 2–3 %, configurable) y método de aforo (34.6) se **configuran desde la app cuando el usuario quiera**, no bloquean el desarrollo |
| Iter. 4 | Sanidad y reproducción | Pendiente | Criterios profesionales (34.18), frecuencias (34.6) |
| Iter. 5 | Economía (costos ≠ gastos ≠ ingresos ≠ pagos) | Pendiente | Clasificación económica (34.4) |
| Iter. 6 | Guías y procedimientos (regla de oro técnica) | **Estructura hecha (00006)**; contenido progresivo | Contenido técnico validado (34.16) |
| Iter. 7 | Indicadores, análisis, recomendaciones, IA | Pendiente | Criterios e indicadores (34.17), política IA/privacidad (34.20) |
| Iter. 8 | Evidencias en Drive, respaldo, seguridad concreta, PWA offline | Pendiente | OAuth Google Drive, política de respaldo (34.12/34.13) |
| Iter. 9 | Roles y permisos reales | Bloqueada | Personas y funciones reales (34.3) |
| Transversal | Pruebas de rendimiento (3.7), despliegue | Tras Iter. 1b | Teléfono real |

**Lo que sí puedo hacer sin ti** (y haré si sigues en automático): Iter. 2 en base de datos con tablas mínimas y **sin inventar catálogos** (estados "pendiente de verificar"), plantillas de guía técnica (estructura, no contenido), y mantener este documento al día. **Lo que no puedo hacer sin inventar:** todo lo que dependa de datos reales de la finca, criterios sanitarios/legales o credenciales.

---
## 5. Reglas vigentes (resumen)
No inventar datos · N/A ≠ 0 · distinguir observado/medido/estimado/calculado/externo/pronosticado/validado · ejecutado ≠ verificado ≠ cerrado · nada se borra, se anula · auditoría append-only · IA propone, humano decide · conflictos críticos a revisión humana · migraciones aditivas · toda decisión de apoyo guarda datos, método, fórmula, fecha, fuente, evidencia, usuario y versión del criterio.

---
## 6. PROMPT DE CONTINUIDAD (copiar a una conversación nueva)

> Eres el arquitecto funcional y técnico del "Sistema Agroecológico Integral para Finca" (Caquetá, Colombia), app Flutter + Supabase (Postgres/PostGIS/Auth/RLS) + Drift + PowerSync + Google Drive, cloud-first con offline. Automatización activa desde 30-sep-2026: decide en modo recomendado y pregunta solo si es estrictamente necesario. La fuente de verdad es el DOCUMENTO MAESTRO V5 adjunto (sustituye a V4, que sigue vigente salvo cambios explícitos). No modifiques decisiones aprobadas sin señalar la contradicción y pedir PREAPROBACIÓN REQUERIDA. No inventes datos de la finca ni criterios técnicos/sanitarios/legales.
>
> **Estado:** migraciones 00002–00004 escritas y probadas en Postgres 16+PostGIS sobre una reconstrucción de 00001 (58 comprobaciones, 0 fallas); módulos Flutter QR y mapa escritos pero SIN COMPILAR. Decisiones DT-008–DT-015 en V5 §2. Bloque 34.2 propuesto en V5 §3 (números sin aprobar).
>
> **Punto exacto de continuidad:** (1) correr 00002–00004 en el Supabase real y comprobar `lotes_ganaderos` (DT-011); (2) recibir los archivos Flutter reales (app_database.dart, providers, animal_form_screen.dart, pubspec, tema) y conectar QR/mapa/lotes; (3) aprobar o corregir DT-009 y los objetivos de 3.4; (4) continuar con la Iteración 2 (ganadería base) sin inventar catálogos.
>
> **Pendientes por fase:** 34.1–34.20 según V5 §4; lo que dependa de datos reales o credenciales queda en "esperando información".

---
## CHG-010 (30-sep-2026 23:41) — Alineación con el Prompt Maestro nuevo
- Contradicción detectada: el prompt nuevo (§62, §101) deja el stack y la base física como pendientes y la programación como no iniciada; V5 tenía D-021 como decidida.
- Resolución del usuario: lo construido se mantiene; la arquitectura es la base. Existía un avance previo en Antigravity.
- Efecto: D-021, DT-010, DT-013 y §3.9 pasan a "propuesta / existente" hasta 3.2. SQL 00002–00007 y Dart = borrador de entrada de 3.3. Las reglas de negocio no cambian.
- Punto de continuidad: FASE 3 → 3.1 Arquitectura técnica general (docs/FASE3_1_ARQUITECTURA_TECNICA_GENERAL.md, pendiente de aprobación) → 3.2 Selección tecnológica.
- Pendientes nuevos del prompt: no reasignar QR con operaciones pendientes; foto tipo "identificación"; campos adicionales de guía; estados de calidad de datos; separar fecha del hecho/registro/sincronización.

---
## CHG-011 (30-sep-2026 23:44) — Aprobación expresa del stack
- Instrucción del usuario: "debemos construir ya".
- D-021 (Flutter + Supabase/Postgres/PostGIS + Drift + PowerSync + flutter_map + Google Drive) pasa a **APROBADA** por el usuario. Revierte el estado "propuesta" de CHG-010 solo para el stack.
- Se mantiene del prompt: IA (proveedor/modelo), mapas (proveedor de teselas), roles/permisos reales y RPO/RTO siguen pendientes; se resuelven al llegar a su componente, sin frenar la construcción.
- 3.1 se considera aprobado. Se continúa construyendo por componente (§99), marcando como pendiente lo que falte.

---
## CHG-012 (30-sep-2026 23:50) — Migración 00008 (alineación con el Prompt Maestro)
- QR: no se reasigna un QR con operaciones pendientes de revisión (resultado `rechazada: operaciones_pendientes`); tras revisarlas se puede reasignar.
- Evidencias: tipo de foto `identificacion` añadido (D-006 se amplía; antes: principal, serie_corporal, zona_especifica, ubre).
- Calidad de datos: dominio `estado_calidad_dato` (pendiente, registrado, en_revision, validado, inconsistente, rechazado, corregido, reemplazado, no_disponible, no_aplica) + `nota_calidad` en pesajes, aforos y evidencias. Estados problemáticos exigen nota; validar un pesaje exige validador. Nada se borra automáticamente.
- Fechas: `sincronizada_en` la fija el servidor (hecho ≠ registro ≠ sincronización). Filas anteriores a 00008 quedan en NULL = no disponible (no se inventa).
- Validación: `supabase/tests/run_all.sh` corre 00→08 desde cero; 0 fallas.
- Pendientes que NO se tocaron: campos adicionales de guías (§ guías del prompt), catálogo de eventos de vida, 5 categorías (necesita valores reales almacenados), motor de cálculo versionado (siguiente).

---
## CHG-013 (30-sep-2026 23:55) — Modo automático total + migraciones 00009 y 00010
- Autorización del usuario (23:48): modo automático para todo; solo se pide confirmación cuando se requiera sí o sí su aprobación o datos.
- **00009 Motor de cálculo determinístico (D-016):** tablas `criterios_parametros` (versionadas, append-only, exigen fuente) y `calculos` (guardan fórmula, versión, criterio usado, entradas con su naturaleza, faltantes, incertidumbre, usuario; solo-anular). Función `calcular_demanda_ms_lote(finca, lote, fecha)`: demanda_ms_kg_dia = Σ peso vivo × pct/100, con criterio `ms_pct_peso_vivo` vigente a la fecha. Sin criterio, sin peso de algún animal o lote vacío ⇒ NO CALCULABLE (nunca 0, nunca parcial). Pesajes rechazados/reemplazados/inconsistentes no se usan. Un criterio nuevo no reinterpreta cálculos anteriores. **No se sembró ningún valor** (el 2–3 % del prompt es referencia; el administrador define el suyo y su fuente).
- **00010 Guías:** +6 campos del prompt §2 (cuándo, quién puede, equipos, preparación, condiciones de suspensión, criterios de aceptación). Publicar exige los 22 elementos ('no aplica' escrito explícitamente; vacío no vale).
- Validación: `tests/run_all.sh` 00→10 desde cero: 131 verificaciones, 0 fallas.
- Pendientes que requieren al usuario (cuando llegue el momento): valor del criterio MS % peso vivo con su fuente; valores reales almacenados de `categoria`; lista de eventos de vida.
- Siguiente bloque automático: 3.2 Selección tecnológica documentada (con el stack ya aprobado) y 3.3 Modelo físico de datos documentado a partir de 00002–00010.

---
## CHG-014 (30-sep-2026 23:58) — Aforo con varios puntos y % de agua (migración 00011)
- Indicación del usuario: la materia seca se mide al cortar el metro cuadrado en varios puntos del potrero; el sistema debe decir también cuánta agua tiene el pasto.
- Fórmula adoptada (según las imágenes del usuario): **%MS = (peso materia seca ÷ peso materia fresca) × 100**; **%agua = 100 − %MS**. (El mensaje decía "fresca/seca"; se aplica MS/MF por coincidir con las imágenes y con lo ya implementado en 00007. Si se quisiera otra, es una contradicción a confirmar.)
- Estructura: `aforo_muestras` = varios puntos por aforo (punto 1, 2, 3…; área por punto SIN fijar 1 m²; MF al cortar, MS tras el secado → puede quedar pendiente). Vista `v_aforos_resumen`: %MS ponderado ΣMS/ΣMF, %agua, MS g/m², kg MS/ha (conversión 1 g/m² = 10 kg/ha), mínimo y máximo entre puntos, advertencia si hay puntos sin MS. Sin puntos completos ⇒ no_calculable. Puntos rechazados/inconsistentes se excluyen sin borrarse. Aforos antiguos de un solo punto siguen funcionando.
- Decisión sobre categorías y eventos de vida: **no se restringen ni se siembran**. Lo que el usuario necesite y no tenga nombre se registra a mano. (Se retira el pendiente "restringir `categoria` a 5 valores" y "catálogo de eventos de vida" como bloqueantes; quedan como catálogo editable por el usuario cuando se construya su pantalla.)
- Validación: `tests/run_all.sh` 00→11 desde cero: 148 verificaciones, 0 fallas.

---
## CHG-015 (1-oct-2026) — Cierre de la Fase 3 (diseño técnico) bajo modo automático
- Entregados: `docs/FASE3_2_SELECCION_TECNOLOGICA.md` (stack núcleo aprobado; abiertos: teselas, IA, CI/CD, observabilidad), `docs/FASE3_3_MODELO_FISICO_DATOS.md` (diccionario generado de 00002–00011; tablas base reconstruidas, por verificar con el diagnóstico real) y `docs/FASE3_4_a_3_13_DISENO_TECNICO.md` (contratos, frontend, backend, offline/sync, evidencias/Drive, IA, seguridad, auditoría, pruebas, despliegue/backup).
- Estado: **FASE 3 cerrada a nivel suficiente para programar por componente** (§98–§99). Siguen pendientes y marcados: proveedor de IA, teselas, roles reales/matriz, RPO/RTO (propuesta RPO ≤ 7 días), esqueleto Flutter real, compilación Dart, tabla `ia_interacciones`.
- Punto de continuidad: **FASE 4 — PROGRAMACIÓN por componente**; primer componente: capa de datos y pantallas de animales/lotes/QR; luego pasturas+aforo multipunto.

---
## CHG-016 (1-oct-2026) — Migración 00012: registro de IA e incidentes técnicos
- `ia_interacciones` (3.9) e `incidentes_tecnicos` (§66) creadas según el diseño. Sin proveedor/modelo de IA definido (campos libres).
- Validación: `tests/run_all.sh` 00→12 desde cero: 161 verificaciones, 0 fallas.
- Punto de continuidad: Fase 4 por componente (capa de datos y pantallas de animales/lotes/QR sobre el esqueleto Flutter; pasturas + aforo multipunto).

---
## CHG-017 (1-oct-2026 00:20) — Base de datos REAL en Supabase + esqueleto de la app completo
- Conector Supabase conectado por el usuario. La cuenta (organización "Hato Claros") **no tenía proyectos**: no existía base previa. Se creó el proyecto **finca-hato-claros** (ref `zyqwguollzwejpjvtbll`, región sa-east-1 São Paulo, plan gratuito, 0 COP).
- `00001_base.sql` pasa de reconstrucción de prueba a base real (fincas, unidades espaciales, animales, QR, historial QR, auditoría; PostGIS en esquema `extensions`).
- Aplicadas en el proyecto real: 00001–00009, 00011–00014 (00010 incluida dentro de 00006). 22 tablas, todas con RLS.
- **00013**: `crear_finca_inicial(nombre)` (el usuario crea su finca desde la app, sin SQL manual) y `mover_animal_lote(...)` (cambio de lote atómico con historia).
- **00014**: seguridad según el asesor de Supabase: ninguna función ejecutable por anónimos; funciones de trigger no invocables por API. Quedan 3 avisos intencionales (crear_finca_inicial, es_miembro_finca, qr_revisar_operacion: las usa la app con sesión y verifican permisos por dentro).
- **Prueba de humo en el Supabase real** (usuario simulado, transacción deshecha, 0 datos residuales): finca, animal, pesaje→peso_ultimo, potrero+división A1, lote, alerta >2 días, aforo 22 % MS / 78 % agua, demanda MS 10,5 kg, QR asignado, auditoría → 10/10 correctas.
- Pruebas locales 00→14 desde cero: 171 verificaciones, 0 fallas.
- **App (Flutter) escrita completa** sobre el stack aprobado: inicio de sesión, creación de finca, menú por módulos, animales (lista/alta/expediente con pesajes y naturaleza obligatoria, historial de lotes, mover de lote), lotes, potreros (máx. 6) y divisiones, iniciar/terminar pastoreo con alerta, hectáreas por unidad, aforo multipunto con %MS/%agua/kg MS/ha, QR con escáner. Conectada al proyecto real (URL + clave publicable).
- **Bloqueo técnico real**: este entorno no puede descargar Flutter (red bloqueada a storage.googleapis.com/pub.dev) → el código Dart **no está compilado aquí**. Se dejó `.github/workflows/web.yml`: compila, prueba y publica la PWA gratis en GitHub Pages y genera el APK Android. Requiere conectar GitHub (acción única del usuario).
- Pendiente (no bloquea la base): capa offline (Drift + PowerSync) bajo el mismo contrato de repositorios; subida de evidencias a Drive; respaldo periódico.

---
## CHG-018 (1-oct-2026) — Respaldo de la finca (3.13)
- Migración **00015** `exportar_finca(finca)`: JSON con todas las tablas de la finca (incluye anulados y auditoría), formato `finca-respaldo.v1`, respetando permisos. Aplicada en Supabase real; pruebas locales 00→15: 174 verificaciones, 0 fallas.
- App: botón "Descargar respaldo" en el inicio (archivo .json para guardar en Google Drive). Subida automática a Drive: pendiente de autorizar la cuenta de Google (OAuth) cuando se construya la integración con Drive.

---
## CHG-019 (1-oct-2026) — Arquitectura completa en la app (corrección de alcance)
- **Indicación del usuario:** la app publicada era solo el primer componente (animales, lotes, potreros, aforo, QR) y no reflejaba la arquitectura. Exigió: app totalmente interactiva, todas las transversalidades, tareas conectadas automáticamente, área de informes con dashboard, IA, misión y visión, y respeto total de la arquitectura. Se corrige sin modificar ninguna decisión cerrada.
- **Base de datos — migración 00016 `nucleo_integral`** (aplicada en Supabase en 4 partes 00016a–d; pruebas locales 00→16: 204 verificaciones, 0 fallas; prueba en la base real con el usuario, deshecha):
  - Nivel 1: `fuentes_agua` (nacimiento→…→uso, georreferenciación, conservación sin categoría legal), `mediciones_ambientales` (lluvia en mm, 1 mm = 1 L/m²), `muestras_suelo` + `resultados_suelo` (9 análisis del §24).
  - Nivel 2: `infraestructuras` (estados del §22; falla → alerta → reparación → verificación → retorno a servicio), `recursos` (requerido → disponible → … → utilizado).
  - Nivel 3: `sistemas_productivos`, `eventos_sanitarios` (observación → revisión → diagnóstico profesional → tratamiento autorizado → seguimiento → verificación; diagnóstico/tratamiento exigen profesional; no retrocede), `eventos_reproductivos`, `produccion_leche`, `entregas_leche` (entrega ≠ pago), `movimientos_economicos` (costo ≠ gasto ≠ ingreso ≠ pago), `especies`, `lotes_vivero`, `establecimientos`.
  - Nivel 4: `actividades` con la máquina de estados del §26 (ejecutada → requiere verificación → verificada → cerrada; resultado y verificación obligatorios; motivo en bloqueos/cancelaciones).
  - Nivel 5: `indicadores_def` (solo fórmulas acordadas: %MS, %agua, kg MS/ha por puntos, demanda MS, horas de ocupación, días de descanso, lluvia L/m², litros, costo por litro **conceptual**, peso último), `alertas` (un hecho = una alerta; convertir en actividad, decisión o hallazgo).
  - Nivel 6: `hallazgos` (señal/hallazgo/hipótesis/diagnóstico; validar exige quién valida).
  - Nivel 7: `recomendaciones` (recomendación ≠ decisión), `alternativas` (sin ranking), `decisiones` (§27; aprobar exige los elementos del §33).
  - Nivel 8: `aprendizajes` (experiencia → … → conocimiento).
  - Transversales: `observaciones`, `evidencias` (enlace de Drive), misión y visión en `fincas` (las escribe el usuario), anular exige motivo, auditoría y RLS en todas.
  - **Tareas conectadas automáticamente:** entrada de lote → salida programada al límite aprobado (48 h); aforo → completar puntos y MS; observación sanitaria → revisión; tratamiento autorizado → seguimiento; servicio → diagnóstico de gestación (pendiente, sin inventar días); parto → registrar cría; muestra de suelo → enviar → registrar resultados; recurso requerido → conseguir; decisión aprobada → actividad programada (y comprobación si es condicional) → la decisión avanza sola a ejecutándose/cumplida/verificada; actividad verificada con seguimiento → nueva tarea de seguimiento.
  - Funciones: `tablero_finca` (dashboard/informes por periodo), `generar_alertas`, `convertir_alerta`, `buscar_finca`, `cargar_datos_declarados` (datos de §17, §22, §23 y V5 §2.2 con su naturaleza), `crear_guias_base` (9 guías en borrador con el contenido que la arquitectura ya define).
- **App (v0.2.0):** 9 pilares con los 8 niveles; motor genérico (lista, formulario con guía, expediente con siguiente paso, relaciones, actividades/alertas vinculadas, observaciones, evidencias, auditoría, IA); inicio con tablero vivo y flujo dato → mejora; informes por periodo con gráficos y exportación CSV; agenda; búsqueda; mapa con puntos; indicadores y cálculos trazables; guías versionadas (editar, nueva versión, publicar); configuración (misión/visión, criterio de consumo de MS con fuente, datos declarados, respaldo).
- **IA:** función `ia-asistente` desplegada en Supabase; registra todo en `ia_interacciones`; sin clave del proveedor responde "IA no configurada" y la app sigue funcionando. **Proveedor/modelo: pendiente de decisión del usuario (3.9)**; propuesto Anthropic Claude Haiku 4.5 por costo.
- **Verificación:** compilación en GitHub Actions correcta; prueba de extremo a extremo de la app publicada con navegador y backend simulado (inicio de sesión, tablero, 20 pantallas, registro con formulario): 0 errores de la app.
- **Pendientes:** proveedor de IA (clave); configuración de Site URL de Supabase (enlace de confirmación); capa offline (Drift + PowerSync); subida directa a Drive (OAuth); roles reales (34.3); proveedor de mapas (34.8).
