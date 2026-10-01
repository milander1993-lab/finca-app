# FASE 3.3 — Modelo físico de datos (diccionario generado)
Versión 1 · 1-oct-2026 · Estado: **borrador de entrada (propuesta)** generado automáticamente desde las migraciones 00002–00011 aplicadas desde cero en Postgres local de prueba.

**Aviso de verdad (no inventar):** las tablas *fincas, animales, codigos_qr, historial_qr, unidades_espaciales* (y la tabla `auditoria` base) provienen de una **reconstrucción** del esquema 00001 (el SQL real de tu Supabase no se ha verificado). Se confirma con `supabase/diagnostico/00_diagnostico_solo_lectura.sql` cuando lo ejecutes.

## 1. Convenciones físicas (aplican a toda tabla de dominio)
- Clave `id uuid` generada en el cliente (offline-first, reintento sin duplicar).
- `finca_id` en cada tabla; acceso por membresía (`es_miembro_finca`) vía RLS.
- Autoría y versión: `created_at/updated_at/created_by/updated_by/version` (sellados por trigger; el cliente no los falsifica).
- Borrado lógico `is_deleted` (anular ≠ borrar); DELETE bloqueado por trigger y REVOKE.
- Auditoría append-only (`auditoria`) por trigger AFTER INSERT/UPDATE.
- Tres fechas: hecho (campo propio), registro (`created_at`), sincronización (`sincronizada_en`, servidor).
- Naturaleza del dato (`naturaleza_dato`) y estado de calidad (`estado_calidad_dato`) donde aplica.

## 2. Tablas y columnas

### aforo_muestras
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `aforo_id` | uuid | NO |  |
| `punto` | int4 | NO |  |
| `area_muestra_m2` | numeric | sí |  |
| `materia_fresca_g` | numeric | sí |  |
| `materia_seca_g` | numeric | sí |  |
| `observaciones` | text | sí |  |
| `estado_calidad` | varchar(20) | NO | 'registrado'::character varying |
| `nota_calidad` | text | sí |  |
| `sincronizada_en` | timestamptz | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |

### aforos
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `unidad_id` | uuid | NO |  |
| `fecha_aforo` | timestamptz | NO |  |
| `area_muestra_m2` | numeric | sí |  |
| `materia_fresca_g` | numeric | sí |  |
| `materia_seca_g` | numeric | sí |  |
| `metodo` | text | sí |  |
| `guia_version_id` | uuid | sí |  |
| `naturaleza` | varchar(20) | NO |  |
| `responsable_id` | uuid | sí |  |
| `observaciones` | text | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |
| `estado_calidad` | varchar(20) | NO | 'registrado'::character varying |
| `nota_calidad` | text | sí |  |
| `sincronizada_en` | timestamptz | sí |  |

### animal_lote
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `animal_id` | uuid | NO |  |
| `lote_id` | uuid | NO |  |
| `fecha_ingreso` | timestamptz | NO |  |
| `fecha_salida` | timestamptz | sí |  |
| `motivo_ingreso` | text | sí |  |
| `motivo_salida` | text | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |
| `sincronizada_en` | timestamptz | sí |  |

### animales
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | uuid_generate_v4() |
| `finca_id` | uuid | NO |  |
| `numero_interno` | varchar(40) | NO |  |
| `categoria` | varchar(30) | sí |  |
| `sexo` | varchar(10) | sí |  |
| `fecha_nacimiento` | date | sí |  |
| `fecha_nacimiento_naturaleza` | varchar(20) | sí | 'estimada'::character varying |
| `estado` | varchar(20) | sí | 'activo'::character varying |
| `peso_ultimo` | numeric | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |
| `peso_ultimo_naturaleza` | varchar(20) | sí |  |
| `peso_ultimo_fecha` | timestamptz | sí |  |

### auditoria
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | uuid_generate_v4() |
| `actor_id` | uuid | sí |  |
| `accion` | text | sí |  |
| `tabla_afectada` | text | sí |  |
| `registro_id` | uuid | sí |  |
| `estado_anterior` | jsonb | sí |  |
| `estado_nuevo` | jsonb | sí |  |
| `created_at` | timestamptz | sí | now() |
| `finca_id` | uuid | sí |  |
| `motivo` | text | sí |  |

### calculos
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `codigo_calculo` | text | NO |  |
| `version_formula` | text | NO |  |
| `formula` | text | NO |  |
| `alcance_tipo` | text | NO |  |
| `alcance_id` | uuid | NO |  |
| `periodo_fecha` | timestamptz | NO |  |
| `resultado` | text | NO |  |
| `valor` | numeric | sí |  |
| `unidad` | text | sí |  |
| `naturaleza` | varchar(20) | NO | 'calculado'::character varying |
| `parametro_id` | uuid | sí |  |
| `entradas` | jsonb | NO |  |
| `faltantes` | jsonb | sí |  |
| `incertidumbre` | text | sí |  |
| `calculado_por` | uuid | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |

### codigos_qr
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | uuid_generate_v4() |
| `codigo` | text | NO |  |
| `estado` | varchar(20) | sí | 'disponible'::character varying |
| `animal_actual_id` | uuid | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |
| `finca_id` | uuid | sí |  |

### criterios_parametros
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `codigo` | text | NO |  |
| `nombre` | text | NO |  |
| `valor` | numeric | NO |  |
| `unidad` | text | NO |  |
| `vigente_desde` | timestamptz | NO | now() |
| `fuente` | text | NO |  |
| `limitaciones` | text | sí |  |
| `validador_id` | uuid | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |

### destinos_superficie
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `destino` | text | NO |  |
| `superficie_ha` | numeric | NO |  |
| `naturaleza` | varchar(20) | NO |  |
| `observaciones` | text | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |

### evidencias_animal
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `animal_id` | uuid | NO |  |
| `tipo` | text | NO |  |
| `angulo` | text | sí |  |
| `zona` | text | sí |  |
| `tomada_en` | timestamptz | NO |  |
| `naturaleza` | varchar(20) | NO | 'observado'::character varying |
| `estado_subida` | text | NO | 'pendiente_sincronizacion'::text |
| `drive_file_id` | text | sí |  |
| `drive_miniatura_id` | text | sí |  |
| `sha256` | text | sí |  |
| `mime` | text | sí |  |
| `bytes` | int8 | sí |  |
| `intentos_subida` | int4 | NO | 0 |
| `ultimo_error` | text | sí |  |
| `observaciones` | text | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |
| `estado_calidad` | varchar(20) | NO | 'registrado'::character varying |
| `nota_calidad` | text | sí |  |
| `sincronizada_en` | timestamptz | sí |  |

### finca_miembros
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `user_id` | uuid | NO |  |
| `activo` | bool | NO | true |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |

### fincas
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | uuid_generate_v4() |
| `nombre` | text | NO |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |

### guia_versiones
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `guia_id` | uuid | NO |  |
| `numero` | int4 | NO |  |
| `estado` | text | NO | 'borrador'::text |
| `que_es` | text | sí |  |
| `para_que` | text | sí |  |
| `por_que` | text | sí |  |
| `donde` | text | sí |  |
| `como` | text | sí |  |
| `metodo` | text | sí |  |
| `materiales` | text | sí |  |
| `unidades` | text | sí |  |
| `pasos` | text | sí |  |
| `precauciones` | text | sí |  |
| `errores_comunes` | text | sí |  |
| `prohibiciones` | text | sí |  |
| `registro` | text | sí |  |
| `evidencia` | text | sí |  |
| `validacion` | text | sí |  |
| `seguimiento` | text | sí |  |
| `fuente` | text | sí |  |
| `revisado_por` | uuid | sí |  |
| `publicada_en` | timestamptz | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |
| `cuando` | text | sí |  |
| `quien_puede` | text | sí |  |
| `equipos` | text | sí |  |
| `preparacion` | text | sí |  |
| `condiciones_suspension` | text | sí |  |
| `criterios_aceptacion` | text | sí |  |

### guias
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `codigo` | text | NO |  |
| `titulo` | text | NO |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |

### historial_qr
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | uuid_generate_v4() |
| `codigo_qr_id` | uuid | NO |  |
| `animal_id` | uuid | NO |  |
| `fecha_asignacion` | timestamptz | NO | now() |
| `fecha_liberacion` | timestamptz | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |
| `finca_id` | uuid | sí |  |
| `motivo_asignacion` | text | sí |  |
| `motivo_liberacion` | text | sí |  |
| `asignado_por` | uuid | sí |  |
| `liberado_por` | uuid | sí |  |
| `confirmada_en` | timestamptz | sí |  |

### lotes_ganaderos
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `nombre` | text | NO |  |
| `estado` | varchar(20) | NO | 'activo'::character varying |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |

### ocupaciones_pastoreo
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `unidad_id` | uuid | NO |  |
| `lote_id` | uuid | NO |  |
| `entrada_en` | timestamptz | NO |  |
| `salida_en` | timestamptz | sí |  |
| `observaciones` | text | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |
| `sincronizada_en` | timestamptz | sí |  |

### pesajes
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `animal_id` | uuid | NO |  |
| `fecha_pesaje` | timestamptz | NO |  |
| `valor` | numeric | NO |  |
| `unidad` | varchar(10) | NO | 'kg'::character varying |
| `naturaleza` | varchar(20) | NO |  |
| `metodo` | varchar(80) | sí |  |
| `responsable_id` | uuid | sí |  |
| `evidencia_ref` | text | sí |  |
| `validado_por` | uuid | sí |  |
| `validado_en` | timestamptz | sí |  |
| `observaciones` | text | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |
| `estado_calidad` | varchar(20) | NO | 'registrado'::character varying |
| `nota_calidad` | text | sí |  |
| `sincronizada_en` | timestamptz | sí |  |

### qr_operaciones
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | gen_random_uuid() |
| `finca_id` | uuid | NO |  |
| `codigo` | text | NO |  |
| `operacion` | text | NO |  |
| `animal_id` | uuid | sí |  |
| `motivo` | text | sí |  |
| `estado_esperado` | text | sí |  |
| `creada_en` | timestamptz | NO |  |
| `estado` | text | NO | 'pendiente'::text |
| `resultado_detalle` | jsonb | sí |  |
| `aplicada_en` | timestamptz | sí |  |
| `revisado_por` | uuid | sí |  |
| `revisado_en` | timestamptz | sí |  |
| `nota_revision` | text | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |
| `sincronizada_en` | timestamptz | sí |  |

### unidades_espaciales
| columna | tipo | nulo | por defecto |
|---|---|---|---|
| `id` | uuid | NO | uuid_generate_v4() |
| `finca_id` | uuid | NO |  |
| `parent_id` | uuid | sí |  |
| `tipo` | varchar(40) | sí |  |
| `nombre` | text | sí |  |
| `geometria` | geometry | sí |  |
| `es_temporal` | bool | sí | false |
| `estado` | varchar(20) | sí |  |
| `created_at` | timestamptz | NO | now() |
| `updated_at` | timestamptz | NO | now() |
| `created_by` | uuid | sí |  |
| `updated_by` | uuid | sí |  |
| `version` | int4 | NO | 1 |
| `is_deleted` | bool | NO | false |
| `geometria_naturaleza` | varchar(20) | sí |  |
| `superficie_ha` | numeric | sí |  |
| `superficie_naturaleza` | varchar(20) | sí |  |

## 3. Vistas
- `geography_columns`
- `geometry_columns`
- `v_aforos_calculo`
- `v_aforos_resumen`
- `v_alertas_ocupacion`
- `v_unidades_mapa`

## 4. Triggers de reglas (autoridad en servidor, DT-012)
| tabla | trigger | momento |
|---|---|---|
| aforo_muestras | t10_sellar_autoria | BEFORE |
| aforo_muestras | t12_sincronizacion_ins | BEFORE |
| aforo_muestras | t12_sincronizacion_upd | BEFORE |
| aforo_muestras | t20_timestamps | BEFORE |
| aforo_muestras | t30_bloquear_delete | BEFORE |
| aforo_muestras | t50_aforo_muestras_reglas | BEFORE |
| aforo_muestras | t55_calidad_dato | BEFORE |
| aforo_muestras | t90_auditar | AFTER |
| aforos | t10_sellar_autoria | BEFORE |
| aforos | t12_sincronizacion_ins | BEFORE |
| aforos | t12_sincronizacion_upd | BEFORE |
| aforos | t20_timestamps | BEFORE |
| aforos | t30_bloquear_delete | BEFORE |
| aforos | t50_aforos_reglas | BEFORE |
| aforos | t55_calidad_dato | BEFORE |
| aforos | t90_auditar | AFTER |
| animal_lote | t10_sellar_autoria | BEFORE |
| animal_lote | t12_sincronizacion_ins | BEFORE |
| animal_lote | t12_sincronizacion_upd | BEFORE |
| animal_lote | t20_timestamps | BEFORE |
| animal_lote | t30_bloquear_delete | BEFORE |
| animal_lote | t50_animal_lote | BEFORE |
| animal_lote | t90_auditar | AFTER |
| animales | t10_sellar_autoria | BEFORE |
| animales | t20_timestamps | BEFORE |
| animales | t30_bloquear_delete | BEFORE |
| animales | t90_auditar | AFTER |
| auditoria | t10_auditoria_inmutable | BEFORE |
| auditoria | t10_auditoria_sin_truncate | BEFORE |
| calculos | t10_sellar_autoria | BEFORE |
| calculos | t20_timestamps | BEFORE |
| calculos | t30_bloquear_delete | BEFORE |
| calculos | t50_solo_anular | BEFORE |
| calculos | t90_auditar | AFTER |
| codigos_qr | t10_sellar_autoria | BEFORE |
| codigos_qr | t20_timestamps | BEFORE |
| codigos_qr | t30_bloquear_delete | BEFORE |
| codigos_qr | t50_qr_transicion | BEFORE |
| codigos_qr | t90_auditar | AFTER |
| criterios_parametros | t10_sellar_autoria | BEFORE |
| criterios_parametros | t20_timestamps | BEFORE |
| criterios_parametros | t30_bloquear_delete | BEFORE |
| criterios_parametros | t50_solo_anular | BEFORE |
| criterios_parametros | t90_auditar | AFTER |
| destinos_superficie | t10_sellar_autoria | BEFORE |
| destinos_superficie | t20_timestamps | BEFORE |
| destinos_superficie | t30_bloquear_delete | BEFORE |
| destinos_superficie | t90_auditar | AFTER |
| evidencias_animal | t10_sellar_autoria | BEFORE |
| evidencias_animal | t12_sincronizacion_ins | BEFORE |
| evidencias_animal | t12_sincronizacion_upd | BEFORE |
| evidencias_animal | t20_timestamps | BEFORE |
| evidencias_animal | t30_bloquear_delete | BEFORE |
| evidencias_animal | t50_evidencias_reglas | BEFORE |
| evidencias_animal | t55_calidad_dato | BEFORE |
| evidencias_animal | t90_auditar | AFTER |
| finca_miembros | t10_sellar_autoria | BEFORE |
| finca_miembros | t20_timestamps | BEFORE |
| finca_miembros | t30_bloquear_delete | BEFORE |
| finca_miembros | t90_auditar | AFTER |
| fincas | t10_sellar_autoria | BEFORE |
| fincas | t20_timestamps | BEFORE |
| fincas | t30_bloquear_delete | BEFORE |
| fincas | t90_auditar | AFTER |
| guia_versiones | t10_sellar_autoria | BEFORE |
| guia_versiones | t20_timestamps | BEFORE |
| guia_versiones | t30_bloquear_delete | BEFORE |
| guia_versiones | t45_guia_liberar | BEFORE |
| guia_versiones | t50_guia_reglas | BEFORE |
| guia_versiones | t90_auditar | AFTER |
| guias | t10_sellar_autoria | BEFORE |
| guias | t20_timestamps | BEFORE |
| guias | t30_bloquear_delete | BEFORE |
| guias | t90_auditar | AFTER |
| historial_qr | t10_historial_sin_truncate | BEFORE |
| historial_qr | t10_sellar_autoria | BEFORE |
| historial_qr | t20_timestamps | BEFORE |
| historial_qr | t30_bloquear_delete | BEFORE |
| historial_qr | t50_historial_protegido | BEFORE |
| historial_qr | t90_auditar | AFTER |
| lotes_ganaderos | t10_sellar_autoria | BEFORE |
| lotes_ganaderos | t20_timestamps | BEFORE |
| lotes_ganaderos | t30_bloquear_delete | BEFORE |
| lotes_ganaderos | t90_auditar | AFTER |
| ocupaciones_pastoreo | t10_sellar_autoria | BEFORE |
| ocupaciones_pastoreo | t12_sincronizacion_ins | BEFORE |
| ocupaciones_pastoreo | t12_sincronizacion_upd | BEFORE |
| ocupaciones_pastoreo | t20_timestamps | BEFORE |
| ocupaciones_pastoreo | t30_bloquear_delete | BEFORE |
| ocupaciones_pastoreo | t50_ocupacion_reglas | BEFORE |
| ocupaciones_pastoreo | t90_auditar | AFTER |
| pesajes | t10_sellar_autoria | BEFORE |
| pesajes | t12_sincronizacion_ins | BEFORE |
| pesajes | t12_sincronizacion_upd | BEFORE |
| pesajes | t20_timestamps | BEFORE |
| pesajes | t30_bloquear_delete | BEFORE |
| pesajes | t50_pesajes_coherencia | BEFORE |
| pesajes | t55_calidad_dato | BEFORE |
| pesajes | t60_peso_ultimo | AFTER |
| pesajes | t90_auditar | AFTER |
| qr_operaciones | t10_sellar_autoria | BEFORE |
| qr_operaciones | t12_sincronizacion_ins | BEFORE |
| qr_operaciones | t12_sincronizacion_upd | BEFORE |
| qr_operaciones | t20_timestamps | BEFORE |
| qr_operaciones | t30_bloquear_delete | BEFORE |
| qr_operaciones | t50_qr_aplicar | BEFORE |
| qr_operaciones | t50_qr_op_inmutable | BEFORE |
| qr_operaciones | t90_auditar | AFTER |
| unidades_espaciales | t10_sellar_autoria | BEFORE |
| unidades_espaciales | t20_timestamps | BEFORE |
| unidades_espaciales | t30_bloquear_delete | BEFORE |
| unidades_espaciales | t40_geometria_valida | BEFORE |
| unidades_espaciales | t45_potreros_reglas | BEFORE |
| unidades_espaciales | t46_superficie_naturaleza | BEFORE |
| unidades_espaciales | t90_auditar | AFTER |

## 5. Funciones del dominio
- `_postgis_deprecate()`
- `actualizar_timestamps()`
- `addauth()`
- `addgeometrycolumn()`
- `addgeometrycolumn()`
- `addgeometrycolumn()`
- `aforo_muestras_reglas()`
- `aforos_reglas()`
- `animal_lote_coherencia()`
- `auditar_cambio()`
- `auditoria_inmutable()`
- `bloquear_delete()`
- `bloquear_truncate()`
- `calcular_demanda_ms_lote()`
- `calidad_dato_reglas()`
- `checkauth()`
- `disablelongtransactions()`
- `dropgeometrycolumn()`
- `dropgeometrycolumn()`
- `dropgeometrycolumn()`
- `dropgeometrytable()`
- `enablelongtransactions()`
- `evidencias_animal_reglas()`
- `find_srid()`
- `geometria_valida()`
- `get_proj4_from_srid()`
- `guia_versiones_liberar_publicada()`
- `guia_versiones_reglas()`
- `historial_qr_protegido()`
- `lockrow()`
- `longtransactionsenabled()`
- `ocupacion_reglas()`
- `pesajes_coherencia()`
- `populate_geometry_columns()`
- `populate_geometry_columns()`
- `postgis_extensions_upgrade()`
- `postgis_full_version()`
- `potreros_reglas()`
- `proteger_sincronizacion()`
- `qr_operaciones_aplicar()`
- `qr_operaciones_inmutable()`
- `qr_revisar_operacion()`
- `qr_transicion_valida()`
- `sellar_autoria()`
- `sellar_sincronizacion()`
- `sincronizar_peso_ultimo()`
- `solo_anular()`
- `st_bdmpolyfromtext()`
- `st_bdpolyfromtext()`
- `st_findextent()`
- `st_findextent()`
- `st_letters()`
- `superficie_naturaleza_exigida()`
- `unlockrows()`
- `updategeometrysrid()`
- `updategeometrysrid()`
- `updategeometrysrid()`

## 6. Pendientes de 3.3 (no inventar)
- Confirmar el esquema real (diagnóstico) y reconciliar con la reconstrucción.
- Tablas aún inexistentes de niveles superiores: infraestructura/equipos, suelo y agua (análisis), clima, vivero, compostaje, sanidad, reproducción, leche, economía, actividades, indicadores, decisiones, incidentes técnicos, usuarios/roles reales.
- Índices por patrón de consulta real (se afinan al medir).
- Particionamiento: no necesario con 6→100 animales (estimación, no medición).

## 7. Adenda 00012 (1-oct-2026)
- `ia_interacciones`: función, contexto, entrada, salida, datos consultados, incertidumbre, modelo/versión (texto libre: proveedor pendiente), estado (registrada/revisada/aceptada/descartada/fallida), acción humana (una vez, con fecha). La salida no se reescribe; aceptar/descartar exige acción humana.
- `incidentes_tecnicos`: tipo (sincronizacion/datos/sistema/seguridad/otro), severidad, estado (abierto→en_análisis→resuelto→cerrado), resolución obligatoria al resolver/cerrar; cerrado no se modifica.
- Ambas con RLS por finca, auditoría, `sincronizada_en`, sin DELETE.
