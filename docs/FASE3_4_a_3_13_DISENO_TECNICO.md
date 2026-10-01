# FASE 3.4 a 3.13 — Diseño técnico (cierre de Fase 3)
Versión 1 · 1-oct-2026 · Estado: **propuesta consolidada bajo modo automático (CHG-013)**. Cada punto indica si ya está implementado/validado, o pendiente (no inventado). Base: 3.1 (arquitectura), 3.2 (stack aprobado), 3.3 (modelo físico).

## 3.4 Contratos y API
- **Decisión:** no se inventa una API REST propia. El cliente usa la API generada por Supabase (PostgREST) bajo RLS, más funciones SQL (`rpc`) para operaciones con reglas: `calcular_demanda_ms_lote`, `qr_revisar_operacion`.
- **Patrón de escritura crítica (implementado):** el cliente inserta una **operación con id propio** (ej. `qr_operaciones`); el servidor decide `aplicada | rechazada | conflicto` y lo escribe en la misma fila. El cliente no da éxito por sí mismo (DT-015).
- **Patrón de escritura simple:** INSERT/UPDATE directos sobre tablas con RLS y triggers (pesajes, aforos, muestras, ocupaciones…).
- **Errores:** códigos de Postgres estandarizados (`check_violation`, `restrict_violation`, `insufficient_privilege`, `unique_violation`) → el cliente los traduce a mensajes claros. Pendiente: tabla de mensajes (se arma con la pantalla).
- **Versionado de contrato:** columna `version` por fila + versión de fórmula/criterio/guía. Pendiente: política de compatibilidad de la app con versiones de esquema (3.13).

## 3.5 Arquitectura frontend
- Estructura por *feature* (`lib/features/<modulo>/{domain,data,presentation}`), ya iniciada con `qr` y `mapa`.
- Capa de datos como **interfaces** (DT-010): la pantalla nunca llama a Supabase directo; permite probar sin red y cambiar de proveedor.
- Estado con Riverpod; navegación go_router; Material 3; colores por área (agroecología verde, ganadería rojo, infraestructura amarillo) — diseño visual definitivo **PENDIENTE — FASE POSTERIOR**.
- Interfaz: módulos y submódulos con campos dinámicos; sin formularios gigantes; cada medición abre su guía (regla de oro).
- Estados de dato siempre visibles: medido / estimado / calculado / sin datos / no calculable (nunca 0 por falta de dato).
- Pendiente: esqueleto real de la app (archivos del proyecto Flutter) para integrar; compilación.

## 3.6 Backend y dominio
- La **autoridad de reglas está en PostgreSQL** (triggers + funciones), no en el cliente (DT-012). Reglas validadas: QR único/estados, máx. 6 potreros, divisiones temporales, ocupación >2 días → alerta, un lote abierto por animal, guías inmutables, cálculos append-only.
- No hay servidor de aplicación propio. Si algo exige lógica fuera de la base (IA, exportes, Drive), se usan *Edge Functions* de Supabase; pendiente de definir en 3.9 y 3.8.

## 3.7 Offline y sincronización
- Local: Drift (SQLite) como caché y **cola de operaciones**; PowerSync sincroniza las tablas filtradas por `finca_miembros`.
- Reglas de sincronización (a configurar en PowerSync): **no subir `auditoria` desde el cliente**; bajar solo filas de fincas donde el usuario es miembro.
- Clasificación de conflictos (§94): seguro (filas nuevas por id de cliente; MS tras secado) · requiere revisión (`conflicto` QR) · crítico (QR, ocupación) → intervención humana. Sin "última escritura gana" (D-026).
- Estados visibles al usuario: pendiente · enviando · aplicada · rechazada · conflicto · error.
- Pendiente (verificación): PowerSync en Flutter web; tamaño de la caché local en teléfonos de gama baja (medir, no suponer).

## 3.8 Evidencias y Google Drive
- Metadatos en BD (`evidencias_animal`, tipos: principal, identificación, serie corporal, zona específica, ubre), archivo en Drive, hash `sha256`, estados `pendiente_sincronizacion | subida | error` (implementado).
- Flujo: guardar el registro primero (offline) → cola de subida → al subir se escribe `drive_file_id`; una evidencia subida no cambia de archivo; corregir = nueva evidencia.
- Cuenta/permiso de Drive: usa tu Google One (5 TB). Pendiente (necesita tu autorización/credenciales cuando se construya): cuenta de servicio o OAuth y carpeta raíz.
- Estructura de carpetas propuesta: `Finca/Evidencias/<año>/<animal|potrero|…>/` (propuesta, no decisión).

## 3.9 IA
- Servicio **auxiliar y registrado**: toda llamada guarda contexto, entrada, salida, usuario, fecha, modelo, versión e incertidumbre (tabla `ia_interacciones` — **por crear**, aún no existe).
- Lee solo contexto autorizado por RLS; nunca escribe datos críticos; propone y un humano decide (§75). No calcula (D-016).
- Proveedor/modelo: **PENDIENTE** (prompt §61). Decisión con costo en COP cuando se llegue; el tope de 50.000 COP/mes aplica.
- Funciones iniciales previstas (cada una con ficha §85): explicar guía, señalar datos faltantes, resumir ocupación/aforo. Sin imágenes hasta definir guía fotográfica (34.9).

## 3.10 Seguridad
- Implementado: RLS por membresía de finca en toda tabla; `anon` sin acceso; sin DELETE; auditoría append-only; funciones con `search_path` fijo; operaciones QR `SECURITY DEFINER` con verificación de membresía.
- Pendiente (requiere usuarios reales): roles y matriz de permisos (§51); hoy todo miembro puede registrar. Criticidad baja/media/alta y separación proponer→aprobar se aplican al definir roles.
- Secretos: nunca en el código del cliente; claves de servicio solo en el servidor. Revisión de seguridad antes de producción (3.12).

## 3.11 Auditoría y versionado
- Implementado: tabla `auditoria` (quién, qué, cuándo, antes/después), versión por fila, guías/criterios/fórmulas versionados, historia por tablas de vigencia (`animal_lote`, `historial_qr`, `ocupaciones_pastoreo`).
- Pendiente: flujo de cambios de catálogo/criterio con propuesta→revisión→aprobación (§50) cuando existan roles; reversión = nueva versión, nunca borrado.

## 3.12 Pruebas
- Implementado: 148 verificaciones SQL (`supabase/tests/run_all.sh`, 00→11 desde cero, 0 fallas) sobre Postgres local con simulacro de Supabase (`SOLO_PRUEBA`).
- Pendiente: pruebas Dart (escritas, **no ejecutadas**); pruebas de sincronización/offline; pruebas contra un proyecto Supabase real; pruebas en teléfono real.
- Trazabilidad: cada regla de negocio ↔ prueba (matriz conceptual §59; códigos definitivos al diseñar la matriz).

## 3.13 Despliegue, backup y recuperación
- Entornos: **prueba** (proyecto Supabase aparte) y **producción**; las migraciones se aplican primero en prueba (runbook).
- Backup: el plan gratuito **no** respalda automáticamente → exportación periódica (SQL/CSV) a Drive; frecuencia a definir. Restauración: se prueba en el proyecto de prueba.
- RPO/RTO: **PENDIENTES de tu definición** (qué pérdida de datos tolerarías); propuesta inicial para tu aprobación: RPO ≤ 7 días mientras sea plan gratuito.
- Actividad semanal: al estar en plan gratuito, abrir/usar el sistema al menos una vez por semana evita la pausa por inactividad (o un *ping* programado).
- Despliegue web (PWA): hosting estático a elegir (propuesta: el que no genere costo).

## Cierre de Fase 3 y paso a Fase 4
Condición del prompt (§98): cerradas las decisiones del componente a programar. Para los componentes ya construidos (QR, mapa, lotes, pasturas/aforos, evidencias, guías, cálculo) están cumplidas en la base de datos. **Pasa a Fase 4 (programación) por componente**, empezando por lo que no depende de datos que faltan: (1) pantallas de animales/lotes/QR sobre el esqueleto, (2) pasturas y aforo con varios puntos, (3) mapa y superficies, (4) guías, (5) sincronización y evidencias. Cada componente cumple §99 antes de programarse.
