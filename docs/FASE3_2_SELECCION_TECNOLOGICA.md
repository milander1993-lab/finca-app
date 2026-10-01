# FASE 3.2 — Selección tecnológica
Versión 1 · 1-oct-2026 · Autoridad: aprobación expresa del usuario (CHG-011, 30-sep 23:44) y modo automático total (CHG-013).

## 1. Estados (prompt §68)
| Elemento | Estado | Fundamento |
|---|---|---|
| Google Drive para evidencias | **Aprobada** | Prompt maestro (§101) |
| Cliente multiplataforma Flutter (Material 3, go_router, Riverpod), PWA/web + Android | **Aprobada** | CHG-011; cumple "abrir en cualquier teléfono o navegador" (DT-017) |
| Base de datos: PostgreSQL + PostGIS, con RLS | **Aprobada** | CHG-011; reglas críticas en triggers (DT-012) ya validadas |
| Autenticación: Supabase Auth | **Aprobada** | Parte del stack aprobado |
| Plataforma de nube: Supabase (plan gratuito al inicio) | **Aprobada** | CHG-011; costo cumple DT-019 (≤ 50.000 COP/mes) |
| Almacenamiento local y cola offline: Drift (SQLite) | **Aprobada** | CHG-011 |
| Sincronización: PowerSync | **Aprobada con verificación pendiente** | Falta verificar soporte de Flutter web (ver riesgos) |
| Mapas: flutter_map | **Aprobada**; proveedor de teselas **pendiente** | Elegir proveedor y modo offline con datos reales de uso |
| IA: proveedor y modelo | **Pendiente** | Prompt §61: no existe decisión; se define en 3.9 |
| CI/CD, observabilidad, hosting web | **Pendiente** (3.12/3.13) | Opciones listadas abajo |

## 2. Alternativas evaluadas y razón (para trazabilidad)
| Decisión | Alternativa | Ventaja de la alternativa | Desventaja frente a lo aprobado |
|---|---|---|---|
| Cliente | PWA pura (React/Vue) | Un solo artefacto web | Cámara/QR/GPS/offline requieren más trabajo propio; cola offline robusta más difícil |
| Cliente | Nativo Android/iOS por separado | Máximo rendimiento | Dos bases de código; no cumple "cualquier navegador" |
| Backend | Servidor propio (Node/Python + Postgres) | Control total | Operarlo cuesta tiempo y dinero; Supabase ya entrega Auth, RLS y API |
| Sync | Sincronización escrita a mano | Sin costo ni dependencia | Alto riesgo en conflictos (D-026); mucho trabajo |
| Sync | Sin sincronizar (solo online) | Simplicidad | Viola offline (decisión cerrada) |

## 3. Costos (verificados 30-sep-2026; TRM $3.341,23)
- Inicio: Supabase Free + PowerSync Free = **0 COP/mes**.
- Si se pagara Supabase Pro: ≈ US$25 (~$83.531 COP; ~$99.402 con IVA 19 %, aplicabilidad del IVA por confirmar).
- Ambos Pro: ≈ $247.251 COP (≈ $294.229 con IVA) → **supera** el tope de 50.000 COP: no se contrata sin tu autorización.
- Riesgos del plan gratuito: pausa por inactividad de 1 semana; sin respaldo automático → mitigación obligatoria en 3.13 (exportación periódica a Drive).

## 4. Riesgos técnicos abiertos (no ocultar)
1. **Código Dart sin compilar** (el entorno no accede a pub.dev). Se compila y prueba cuando haya entorno con Flutter (o en tu equipo/CI).
2. **PowerSync en Flutter web**: verificar compatibilidad antes de depender de ella para la PWA.
3. **Esquema real de tu Supabase** sin verificar (diagnóstico pendiente de ejecutar por ti).
4. **Avance previo de Antigravity** no entregado: se compara al recibirse; no bloquea.
5. **Dependencia de terceros**: plan gratuito puede cambiar de condiciones → revisar costos cada trimestre.

## 5. Criterio de cierre
Selección cerrada para stack núcleo. Quedan abiertas solo: proveedor de teselas, proveedor/modelo de IA, CI/CD/hosting web, observabilidad. Cada una se decide al llegar a su bloque (3.9, 3.12, 3.13).
