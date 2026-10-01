# FASE 3 — DISEÑO TÉCNICO
## 3.1 Arquitectura técnica general del sistema
Versión 1 · 30-sep-2026 · Estado del bloque: **propuesta para aprobación**

Base: Prompt Maestro de Continuidad (§62–§69, §97–§99). Este bloque define componentes, fronteras, responsabilidades y flujos **sin seleccionar tecnología**. Las tecnologías mencionadas en la sección 14 están en estado "propuesta / existente (prototipo)", nunca "aprobada" (§68).

---
## 0. Decisión de continuidad (CHG-010)
- Decisión anterior: D-021 (stack Flutter/Supabase/Drift/PowerSync) registrada como decidida en modo automático.
- Decisión del usuario (30-sep 23:41): lo ya construido **se mantiene**, pero **la base es la arquitectura**. Además, existía un avance previo hecho en Antigravity (anterior a esta conversación).
- Efecto: D-021 pasa a **"propuesta / existente"**; se evalúa formalmente en 3.2. SQL (00002–00007) y módulos Dart pasan a **"borrador de entrada"** del modelo físico (3.3). Las **reglas de negocio** implementadas se conservan íntegras porque provienen de la arquitectura.
- Pendiente de revisión en 3.2/3.3: el avance de Antigravity (cuando esté disponible) se compara contra este diseño; no se descarta ni se da por válido sin revisión.

## 1. Principios técnicos obligatorios (derivados del prompt)
1. Una sola fuente de verdad; las vistas (mapa, expediente, dashboard, agenda) consultan, no duplican (§70).
2. Lógica crítica en el servidor/persistencia, no solo en el frontend (§69.13).
3. Estado actual + historia; nunca sobrescribir (§72).
4. Offline = el mismo sistema sin conexión (§93).
5. Sin "última escritura gana"; conflictos clasificados (§94).
6. Cálculos determinísticos, trazables y versionados; la IA no calcula (D-016).
7. La IA propone, un humano decide (§75).
8. Dato faltante → pendiente de verificación / no disponible / no calculable (§84).
9. Cada resultado relevante es explicable: datos, fórmula, criterio, periodo, fuente, versión, incertidumbre, evidencia (§90).

## 2. Vista general (capas lógicas)

```
┌────────────────────────────────────────────────────────────────┐
│ C1 CLIENTE (PWA / cualquier teléfono o navegador)              │
│  Presentación · Estado local · Cola de operaciones · Cámara/QR │
│  GPS · Reglas de validación local (espejo, no autoridad)       │
├───────────────▲────────────────────────────────┬───────────────┤
│ C5 SINCRONIZA-│                                │ C7 EVIDENCIAS │
│ CIÓN          │                                │ (Drive)       │
├───────────────┴────────────────────────────────▼───────────────┤
│ C2 SERVICIOS DE DOMINIO (autoridad de reglas)                  │
│  Reglas de negocio · Máquinas de estado · Validación           │
├────────────────────────────────────────────────────────────────┤
│ C3 MOTOR DE CÁLCULO DETERMINÍSTICO (fórmulas/criterios versión)│
│ C4 AUDITORÍA Y VERSIONADO (transversal)                        │
│ C6 AUTENTICACIÓN / AUTORIZACIÓN (membresía, permisos)          │
│ C8 SERVICIO DE IA (contextual, auxiliar, registrado)           │
│ C9 SERVICIO GEOESPACIAL (mapas)                                │
├────────────────────────────────────────────────────────────────┤
│ C10 PERSISTENCIA ÚNICA (modelo de dominio integrado)           │
├────────────────────────────────────────────────────────────────┤
│ C11 OBSERVABILIDAD · C12 PRUEBAS · C13 DESPLIEGUE/RECUPERACIÓN │
└────────────────────────────────────────────────────────────────┘
```

## 3. Fronteras del sistema
**Dentro:** cliente, dominio, persistencia, cálculo, auditoría, sincronización, autorización, servicio de IA, servicio geoespacial, gestión de evidencias.
**Fuera (externos, con contrato):** almacenamiento de archivos (Google Drive, decidido en el prompt), proveedor de IA (pendiente), proveedor de mapas/teselas (pendiente), datos climáticos externos (naturaleza "externo/modelado"), laboratorios (documentos como evidencia).
**Regla:** todo dato que cruza la frontera conserva origen y naturaleza (DA-025).

## 4. Componentes, responsabilidades y qué NO hacen

| ID | Componente | Responsabilidad | No debe |
|---|---|---|---|
| C1 | Cliente | Captura, consulta, cámara, QR, GPS, cola local, caché | Ser autoridad de reglas críticas; borrar historia |
| C2 | Servicios de dominio | Aplicar reglas de negocio y estados (QR, potreros, ocupación, lotes) | Duplicar entidades; saltarse permisos |
| C3 | Motor de cálculo | Ejecutar fórmulas versionadas (%MS, demanda MS, ocupación, área) | Usar IA; asumir valores faltantes |
| C4 | Auditoría/versionado | Registrar quién/qué/cuándo/por qué/antes/después/versión | Permitir editar o borrar el registro |
| C5 | Sincronización | Transportar cambios, ordenar, detectar conflictos, reintentar | Resolver conflictos críticos sola |
| C6 | Autenticación/autorización | Identidad, membresía por finca, permisos por acción, mínimo privilegio | Confiar en el cliente |
| C7 | Evidencias | Metadatos en BD, archivo en Drive, cola de subida, integridad (hash) | Guardar binarios en la BD |
| C8 | IA | Explicar, guiar, señalar faltantes, analizar, proponer | Inventar, decidir, autoaprobarse, modificar criterios |
| C9 | Geoespacial | Geometrías, validación, vistas de mapa, áreas calculadas | Ser base de datos paralela |
| C10 | Persistencia | Modelo integrado, restricciones, historia | Segunda fuente de verdad |
| C11 | Observabilidad | Registrar errores técnicos/incidentes, estado de sincronización | Ocultar errores |
| C12 | Pruebas | Verificar reglas, cálculos, offline, permisos | — |
| C13 | Despliegue/recuperación | Entornos, respaldo, restauración, migraciones | Destruir información pendiente |

## 5. Dominio integrado (resumen de relaciones, no esquema físico)
finca → unidades espaciales (potrero → división) → ocupaciones ↔ lotes ↔ animales; animal → QR, pesajes, evidencias, historial; aforo → %MS; guía versionada ← procedimientos; todo con auditoría. Un objeto real = una entidad (§71, §88).

## 6. Flujo de datos general
1. Captura en cliente → validación local (estructural/rango) → **operación con ID de cliente** en cola local.
2. Sincronización envía la operación → **servicios de dominio validan con autoridad** (permisos, reglas, estados).
3. Resultado explícito: aplicada / rechazada / conflicto. El cliente **no declara éxito** hasta recibir respuesta (DT-015).
4. Persistencia + auditoría en la misma transacción.
5. Cálculos se ejecutan sobre datos persistidos; el resultado guarda datos usados, fórmula, versión, fecha, naturaleza.
6. Vistas (mapa, expediente, dashboard) leen del modelo integrado.
7. IA lee solo contexto autorizado; su salida se registra y requiere revisión humana.

## 7. Persistencia
Una base estructurada única en la nube; local = caché y cola, no fuente de verdad. Cada tabla relevante: identificador generado en cliente, columnas de autoría, versión, borrado lógico (anular ≠ borrar), fecha del hecho / de registro / de modificación / de sincronización (§92). Historia por tablas de vigencia (ej. animal↔lote), no sobrescritura.

## 8. Sincronización (conceptual; 3.7 la concreta)
- Dos clases de operación: **seguras** (se fusionan por campo/registro nuevo) y **críticas** (QR, ocupación, lotes: requieren respuesta del servidor).
- Conflictos: seguro automático / requiere revisión / crítico con intervención humana (§94). Sin "última escritura gana".
- Estados visibles: pendiente · enviando · aplicada · rechazada · conflicto · error.
- Offline conserva reglas, permisos cacheados, validaciones, cola y evidencia pendiente (§93).

## 9. Evidencias y Drive
Metadatos y hash en la BD; archivo en Drive; el registro se guarda primero y la subida va en cola (DT-006). Estados: pendiente_sincronizacion / subida / error. Una evidencia subida no cambia su archivo; corregir = nueva evidencia.

## 10. Autenticación y autorización
Identidad por cuenta; pertenencia por finca (DT-008). Roles reales y matriz de permisos **pendientes** (§51: se definen con usuarios reales; hoy: administrador + 1 colaborador, máx. 3 empleados futuros). Criticidad baja/media/alta, mínimo privilegio, permisos aplicados también offline y verificados en servidor. Separar proponer/revisar/aprobar/implementar/verificar/cerrar según criticidad (§50).

## 11. Motor de reglas y de cálculo
Reglas de negocio ya establecidas (§53): QR único activo, reutilizable tras liberar; >2 días de ocupación = alerta sin inferir causa; faltantes indispensables bloquean cálculo; correcciones conservan historia; fórmula nueva no reinterpreta histórico. Cada cálculo cumple el protocolo §86 (14 puntos) antes de producción; si no, queda "no suficientemente definido". Resultado posible: valor · cero · sin datos · no aplica · no calculable · pendiente · no disponible (distintos entre sí).

## 12. IA (arquitectura funcional; 3.9 la concreta)
Entrada: solo contexto autorizado por usuario y finca. Salida: explicación, guía, faltantes, análisis, propuesta con incertidumbre y datos consultados. Prohibido: inventar, presentar estimación como medición, hipótesis como hecho, observación como diagnóstico, cambiar criterios o auto-aprobarse. Registro: contexto, entrada, salida, usuario, fecha, modelo, versión, incertidumbre, acción humana posterior. Si falla o no sabe: lo dice y no completa. Proveedor y modelo: **pendiente**.

## 13. Mapas, observabilidad, pruebas, despliegue, recuperación
- **Mapas:** vista sobre datos existentes; geometría sin datos = "sin datos"; toda geometría declara naturaleza; áreas calculadas ≠ declaradas.
- **Observabilidad:** incidentes técnicos con estado, errores de sincronización visibles, sin ocultar fallos.
- **Pruebas:** reglas de negocio, cálculos, permisos, estados, offline/conflictos, recuperación; cada requisito traza hasta una prueba (§57).
- **Despliegue:** entornos separados (prueba/producción), migraciones aditivas e idempotentes, versionadas.
- **Recuperación:** respaldo periódico fuera del proveedor principal (ej. exportación a Drive), restauración probada; RPO/RTO **pendientes de definir** con costos reales (límite 50.000 COP/mes, DT-019). Nunca se destruye información pendiente para simplificar recuperación (§95).

## 14. Tecnologías: estado actual (no decisiones)
| Elemento | Estado | Nota |
|---|---|---|
| Google Drive para evidencias | **Decidida** (prompt) | — |
| Flutter (cliente multiplataforma/PWA) | Propuesta / existente | Prototipo de QR y mapa sin compilar |
| Supabase (Postgres, PostGIS, Auth, RLS) | Propuesta / existente | SQL 00002–00007 validado en Postgres local |
| Drift + PowerSync (local + sync) | Propuesta / existente | Soporte web de PowerSync por verificar |
| flutter_map / mapas | Propuesta | Proveedor de teselas y offline pendientes |
| IA (proveedor/modelo) | Pendiente | — |
| Avance previo en Antigravity | Por revisar | Comparar contra este diseño en 3.2 |

## 15. Riesgos y pendientes de este bloque
- Tiers gratuitos pausan por inactividad y no tienen respaldo automático (mitigación: exportación periódica; decisión en 3.13).
- Roles/permisos reales, RPO/RTO, proveedor de IA y mapas: pendientes de sus bloques.
- PENDIENTE — FASE POSTERIOR: diseño visual definitivo, automatizaciones no aprobadas.

## 16. Criterio de cierre del bloque 3.1
Aprobado cuando las fronteras, componentes, responsabilidades y flujo (secciones 3–13) queden aceptados. Siguiente: **3.2 Selección tecnológica** (alternativas con ventajas/desventajas, impacto en la arquitectura y costo en COP; incluye revisar el avance de Antigravity).
