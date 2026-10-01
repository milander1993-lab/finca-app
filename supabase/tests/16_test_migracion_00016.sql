\pset pager off
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
-- Datos declarados y guías base
SELECT 'T datos declarados' t, cargar_datos_declarados('aaaaaaaa-0000-0000-0000-000000000001')->>'resultado' = 'cargados' ok;
SELECT 'T datos declarados no se duplican' t, cargar_datos_declarados('aaaaaaaa-0000-0000-0000-000000000001')->>'resultado' = 'ya_cargados' ok;
SELECT 'T divisiones A1-A3 presentes' t, (SELECT count(*) FROM unidades_espaciales WHERE finca_id='aaaaaaaa-0000-0000-0000-000000000001' AND tipo='division' AND nombre IN ('A1','A2','A3') AND NOT is_deleted) >= 1 ok;
SELECT 'T guías base en borrador' t, crear_guias_base('aaaaaaaa-0000-0000-0000-000000000001') >= 8
   AND NOT EXISTS (SELECT 1 FROM guia_versiones WHERE estado='publicada' AND fuente LIKE 'Prompt Maestro%') ok;
SELECT 'T guías base idempotente' t, crear_guias_base('aaaaaaaa-0000-0000-0000-000000000001') = 0 ok;

-- Actividad: ejecutada → requiere verificación → verificada → cerrada
INSERT INTO actividades (id, finca_id, titulo, fecha_programada) VALUES ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Arreglar cerca', now() + interval '1 day');
DO $$ BEGIN UPDATE actividades SET estado='ejecutada' WHERE id='bbbbbbbb-0000-0000-0000-000000000001'; RAISE NOTICE 'FALLA: ejecutada sin resultado';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK ejecutada exige resultado'; END $$;
UPDATE actividades SET estado='ejecutada', resultado='Se templó el alambre' WHERE id='bbbbbbbb-0000-0000-0000-000000000001';
SELECT 'T ejecutada pasa a requiere_verificacion' t, estado='requiere_verificacion' AND fecha_ejecucion IS NOT NULL ok FROM actividades WHERE id='bbbbbbbb-0000-0000-0000-000000000001';
DO $$ BEGIN UPDATE actividades SET estado='cerrada' WHERE id='bbbbbbbb-0000-0000-0000-000000000001'; RAISE NOTICE 'FALLA: cerró sin verificar';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK no cierra sin verificar'; END $$;
UPDATE actividades SET estado='verificada', verificacion='Revisado en recorrido' WHERE id='bbbbbbbb-0000-0000-0000-000000000001';
UPDATE actividades SET estado='cerrada' WHERE id='bbbbbbbb-0000-0000-0000-000000000001';
SELECT 'T actividad cerrada' t, estado='cerrada' AND fecha_verificacion IS NOT NULL ok FROM actividades WHERE id='bbbbbbbb-0000-0000-0000-000000000001';

-- Decisión: aprobar exige §33; al aprobar se programa la actividad; al verificar la actividad, la decisión queda verificada
INSERT INTO decisiones (id, finca_id, titulo, accion_titulo) VALUES ('cccccccc-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Reparar corral','Comprar postes');
DO $$ BEGIN UPDATE decisiones SET estado='aprobada' WHERE id='cccccccc-0000-0000-0000-000000000001'; RAISE NOTICE 'FALLA: aprobó sin trazabilidad';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK aprobar exige §33'; END $$;
UPDATE decisiones SET estado='aprobada', datos_usados='inspección', metodo='observación', criterio='no aplica', criterio_version='no aplica', fuente='recorrido', evidencia='foto pendiente' WHERE id='cccccccc-0000-0000-0000-000000000001';
SELECT 'T decisión aprobada → programada con actividad' t, d.estado='programada' AND EXISTS (SELECT 1 FROM actividades a WHERE a.origen_tipo='decision' AND a.origen_id=d.id AND a.estado='pendiente') ok
  FROM decisiones d WHERE d.id='cccccccc-0000-0000-0000-000000000001';
UPDATE actividades SET estado='iniciada' WHERE origen_id='cccccccc-0000-0000-0000-000000000001';
SELECT 'T actividad iniciada → decisión ejecutándose' t, estado='ejecutandose' ok FROM decisiones WHERE id='cccccccc-0000-0000-0000-000000000001';
UPDATE actividades SET estado='ejecutada', resultado='Comprados' WHERE origen_id='cccccccc-0000-0000-0000-000000000001';
SELECT 'T actividades hechas → decisión cumplida' t, estado='cumplida' ok FROM decisiones WHERE id='cccccccc-0000-0000-0000-000000000001';
UPDATE actividades SET estado='verificada', verificacion='Factura y postes en finca' WHERE origen_id='cccccccc-0000-0000-0000-000000000001';
SELECT 'T actividades verificadas → decisión verificada' t, estado='verificada' ok FROM decisiones WHERE id='cccccccc-0000-0000-0000-000000000001';

-- Infraestructura: falla → alerta + tarea; reparado → ejecutada; verificada → operativo
UPDATE infraestructuras SET estado='fuera_de_servicio' WHERE nombre='Vivienda principal' AND finca_id='aaaaaaaa-0000-0000-0000-000000000001';
SELECT 'T falla genera alerta y tarea' t,
  EXISTS (SELECT 1 FROM alertas WHERE regla='infraestructura_estado') AND EXISTS (SELECT 1 FROM actividades WHERE clave_auto LIKE 'infra_reparar:%' AND estado='pendiente') ok;
UPDATE infraestructuras SET estado='reparado' WHERE nombre='Vivienda principal' AND finca_id='aaaaaaaa-0000-0000-0000-000000000001';
UPDATE actividades SET estado='verificada', verificacion='Revisada' WHERE clave_auto LIKE 'infra_reparar:%' AND estado='requiere_verificacion';
SELECT 'T verificar reparación devuelve a operativo' t, estado='operativo' ok FROM infraestructuras WHERE nombre='Vivienda principal' AND finca_id='aaaaaaaa-0000-0000-0000-000000000001';

-- Sanidad: observación → tarea de revisión; diagnóstico exige profesional; no retrocede
INSERT INTO eventos_sanitarios (id, finca_id, animal_id, tipo, fecha_hecho, descripcion)
SELECT 'dddddddd-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001', id, 'observacion', now(), 'Cojera leve' FROM animales WHERE finca_id='aaaaaaaa-0000-0000-0000-000000000001' AND NOT is_deleted LIMIT 1;
SELECT 'T observación sanitaria crea tarea' t, EXISTS (SELECT 1 FROM actividades WHERE clave_auto='sanidad_revisar:dddddddd-0000-0000-0000-000000000001') ok;
DO $$ BEGIN UPDATE eventos_sanitarios SET etapa='diagnostico_profesional' WHERE id='dddddddd-0000-0000-0000-000000000001'; RAISE NOTICE 'FALLA: diagnóstico sin profesional';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK diagnóstico exige profesional'; END $$;
UPDATE eventos_sanitarios SET etapa='revision' WHERE id='dddddddd-0000-0000-0000-000000000001';
SELECT 'T revisión ejecuta la tarea' t, estado='requiere_verificacion' ok FROM actividades WHERE clave_auto='sanidad_revisar:dddddddd-0000-0000-0000-000000000001';

-- Reproducción: servicio → diagnóstico pendiente sin fecha inventada
INSERT INTO eventos_reproductivos (finca_id, animal_id, tipo, fecha_hecho)
SELECT 'aaaaaaaa-0000-0000-0000-000000000001', id, 'servicio', now() FROM animales WHERE finca_id='aaaaaaaa-0000-0000-0000-000000000001' AND NOT is_deleted LIMIT 1;
SELECT 'T servicio → diagnóstico pendiente sin fecha' t, EXISTS (SELECT 1 FROM actividades WHERE clave_auto LIKE 'repro_diagnostico:%' AND estado='pendiente' AND fecha_programada IS NULL) ok;

-- Alertas: generar, no duplicar, convertir
INSERT INTO eventos_sanitarios (finca_id, animal_id, tipo, fecha_hecho, descripcion)
SELECT 'aaaaaaaa-0000-0000-0000-000000000001', id, 'observacion', now(), 'Ojo lloroso' FROM animales WHERE finca_id='aaaaaaaa-0000-0000-0000-000000000001' AND NOT is_deleted LIMIT 1;
SELECT 'T generar alertas' t, generar_alertas('aaaaaaaa-0000-0000-0000-000000000001') >= 1 ok;
SELECT 'T alertas sin duplicar' t, generar_alertas('aaaaaaaa-0000-0000-0000-000000000001') = 0 ok;
SELECT 'T convertir alerta en actividad' t, convertir_alerta((SELECT id FROM alertas WHERE regla='sanidad_sin_revision' LIMIT 1), 'actividad', NULL, NULL) IS NOT NULL ok;
SELECT 'T alerta queda trazada al destino' t, estado = 'convertida_actividad' AND destino_id IS NOT NULL ok FROM alertas WHERE regla='sanidad_sin_revision' LIMIT 1;

-- Tablero y búsqueda
SELECT 'T tablero' t, (r->'animales'->>'total') IS NOT NULL AND jsonb_array_length(r->'flujo') = 9 AND (r->'alertas') ? 'lista' ok
  FROM (SELECT tablero_finca('aaaaaaaa-0000-0000-0000-000000000001') r) s;
SELECT 'T búsqueda' t, jsonb_array_length(buscar_finca('aaaaaaaa-0000-0000-0000-000000000001','cerca')) >= 1 ok;
DO $$ BEGIN PERFORM tablero_finca('aaaaaaaa-0000-0000-0000-000000000002'); RAISE NOTICE 'FALLA: tablero de finca ajena';
EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK tablero solo finca propia'; END $$;

-- Anular exige motivo; no se borra
DO $$ BEGIN UPDATE recursos SET is_deleted=true WHERE nombre='Láminas de zinc'; RAISE NOTICE 'FALLA: anuló sin motivo';
EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK anular exige motivo'; END $$;
DO $$ BEGIN DELETE FROM recursos WHERE nombre='Láminas de zinc'; RAISE NOTICE 'FALLA: borró';
EXCEPTION WHEN restrict_violation OR insufficient_privilege THEN RAISE NOTICE 'OK no se borra'; END $$;
SELECT 'T auditoría registra' t, EXISTS (SELECT 1 FROM auditoria WHERE tabla_afectada='decisiones') ok;
RESET ROLE;
