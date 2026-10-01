\pset pager off
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
\set F '''aaaaaaaa-0000-0000-0000-000000000001'''
-- 'P-sin-geo' ya es el potrero 1 (de pruebas anteriores); se agregan 5 más => 6
INSERT INTO unidades_espaciales(finca_id,tipo,nombre) SELECT :F,'potrero','P'||g FROM generate_series(2,6) g;
SELECT 'T 6 potreros principales' t, count(*)=6 ok FROM unidades_espaciales WHERE tipo='potrero' AND NOT is_deleted;
DO $$ BEGIN INSERT INTO unidades_espaciales(finca_id,tipo,nombre) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','potrero','P7'); RAISE NOTICE 'FALLA: séptimo potrero'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK séptimo potrero rechazado (máx. 6)'; END $$;
-- divisiones A1.. libres de nombre
INSERT INTO unidades_espaciales(finca_id,tipo,nombre,es_temporal,parent_id) SELECT :F,'division','A'||g,true,(SELECT id FROM unidades_espaciales WHERE nombre='P2') FROM generate_series(1,3) g;
INSERT INTO unidades_espaciales(finca_id,tipo,nombre,es_temporal,parent_id) VALUES (:F,'division','B1',true,(SELECT id FROM unidades_espaciales WHERE nombre='P3'));
SELECT 'T 4 divisiones (A1,A2,A3,B1)' t, count(*)=4 ok FROM unidades_espaciales WHERE tipo='division';
SELECT 'T las 6 siguen siendo 6 potreros' t, count(*)=6 ok FROM unidades_espaciales WHERE tipo='potrero';
DO $$ BEGIN INSERT INTO unidades_espaciales(finca_id,tipo,nombre,es_temporal,parent_id) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','division','a1',true,(SELECT id FROM unidades_espaciales WHERE nombre='P3')); RAISE NOTICE 'FALLA: nombre duplicado'; EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK nombre de división único (sin distinguir mayúsculas)'; END $$;
DO $$ BEGIN INSERT INTO unidades_espaciales(finca_id,tipo,nombre,es_temporal,parent_id) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','division','X1',false,(SELECT id FROM unidades_espaciales WHERE nombre='P2')); RAISE NOTICE 'FALLA: división permanente'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK división no puede ser permanente'; END $$;
DO $$ BEGIN INSERT INTO unidades_espaciales(finca_id,tipo,nombre,es_temporal) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','division','X2',true); RAISE NOTICE 'FALLA: división sin potrero'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK división exige potrero'; END $$;
DO $$ BEGIN INSERT INTO unidades_espaciales(finca_id,tipo,nombre,es_temporal,parent_id) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','division','X3',true,(SELECT id FROM unidades_espaciales WHERE nombre='A1')); RAISE NOTICE 'FALLA: división dentro de división'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK el padre debe ser un potrero'; END $$;
DO $$ BEGIN UPDATE unidades_espaciales SET es_temporal=false WHERE nombre='A1'; RAISE NOTICE 'FALLA: promovió división'; EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'OK división no se vuelve permanente (DA-047)'; END $$;
DO $$ BEGIN UPDATE unidades_espaciales SET tipo='potrero',parent_id=NULL,es_temporal=false WHERE nombre='A2'; RAISE NOTICE 'FALLA: cambió tipo'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK cambio de tipo bloqueado'; END $$;
-- superficies
DO $$ BEGIN UPDATE unidades_espaciales SET superficie_ha=1.5 WHERE nombre='P2'; RAISE NOTICE 'FALLA: superficie sin naturaleza'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK superficie exige naturaleza'; END $$;
UPDATE unidades_espaciales SET superficie_ha=1.5, superficie_naturaleza='estimado' WHERE nombre='P2';
INSERT INTO destinos_superficie(finca_id,destino,superficie_ha,naturaleza) VALUES (:F,'Ganadería',10.5,'estimado');
DO $$ BEGIN INSERT INTO destinos_superficie(finca_id,destino,superficie_ha,naturaleza) VALUES ('aaaaaaaa-0000-0000-0000-000000000001',' ganadería ',1,'medido'); RAISE NOTICE 'FALLA: destino duplicado'; EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK destino único por finca'; END $$;
DO $$ BEGIN INSERT INTO destinos_superficie(finca_id,destino,superficie_ha,naturaleza) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','Vivero',0,'medido'); RAISE NOTICE 'FALLA: 0 ha'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK 0 ha rechazado (N/A ≠ 0)'; END $$;
DO $$ BEGIN INSERT INTO destinos_superficie(finca_id,destino,superficie_ha) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','Vivero',2); RAISE NOTICE 'FALLA: sin naturaleza'; EXCEPTION WHEN not_null_violation THEN RAISE NOTICE 'OK destino exige naturaleza'; END $$;
-- ocupación
INSERT INTO ocupaciones_pastoreo(finca_id,unidad_id,lote_id,entrada_en) VALUES (:F,(SELECT id FROM unidades_espaciales WHERE nombre='A1'),'dddddddd-0000-0000-0000-000000000001',now()-interval '3 days');
SELECT 'T alerta: 3 días ocupando => excede, sin inventar causa' t, excede_limite AND abierta AND horas_ocupadas BETWEEN 71 AND 73 AND mensaje LIKE '%causa por determinar%' ok FROM v_alertas_ocupacion;
DO $$ BEGIN INSERT INTO ocupaciones_pastoreo(finca_id,unidad_id,lote_id,entrada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000001',(SELECT id FROM unidades_espaciales WHERE nombre='A2'),'dddddddd-0000-0000-0000-000000000001',now()); RAISE NOTICE 'FALLA: lote en dos áreas'; EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK un lote no está en dos áreas a la vez'; END $$;
DO $$ BEGIN INSERT INTO ocupaciones_pastoreo(finca_id,unidad_id,lote_id,entrada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000001',(SELECT id FROM unidades_espaciales WHERE nombre='A1'),'dddddddd-0000-0000-0000-000000000002',now()); RAISE NOTICE 'FALLA: área con dos ocupaciones'; EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK un área no tiene dos ocupaciones abiertas'; END $$;
DO $$ BEGIN INSERT INTO ocupaciones_pastoreo(finca_id,unidad_id,lote_id,entrada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000001',(SELECT id FROM unidades_espaciales WHERE nombre='P2'),'dddddddd-0000-0000-0000-000000000002',now()); RAISE NOTICE 'FALLA: solapamiento potrero/división'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK solapamiento potrero/división rechazado'; END $$;
DO $$ BEGIN INSERT INTO ocupaciones_pastoreo(finca_id,unidad_id,lote_id,entrada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000001',(SELECT id FROM unidades_espaciales WHERE nombre='B1'),'dddddddd-0000-0000-0000-000000000009',now()); RAISE NOTICE 'FALLA: lote ajeno'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK lote de otra finca rechazado'; END $$;
INSERT INTO ocupaciones_pastoreo(finca_id,unidad_id,lote_id,entrada_en) VALUES (:F,(SELECT id FROM unidades_espaciales WHERE nombre='B1'),'dddddddd-0000-0000-0000-000000000002',now()-interval '1 hour');
SELECT 'T sin alerta a la hora de ocupar' t, NOT excede_limite ok FROM v_alertas_ocupacion WHERE unidad_nombre='B1';
DO $$ BEGIN UPDATE ocupaciones_pastoreo SET lote_id='dddddddd-0000-0000-0000-000000000002' WHERE entrada_en < now()-interval '2 days'; RAISE NOTICE 'FALLA: reescribió'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK ocupación no se reescribe'; END $$;
UPDATE ocupaciones_pastoreo SET salida_en=now() WHERE entrada_en < now()-interval '2 days';
SELECT 'T cerrada sigue registrando que excedió' t, NOT abierta AND excede_limite ok FROM v_alertas_ocupacion WHERE unidad_nombre='A1';
DO $$ BEGIN DELETE FROM ocupaciones_pastoreo; RAISE NOTICE 'FALLA delete'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK delete bloqueado'; END $$;
-- aforo
INSERT INTO aforos(finca_id,unidad_id,fecha_aforo,area_muestra_m2,materia_fresca_g,materia_seca_g,naturaleza) VALUES (:F,(SELECT id FROM unidades_espaciales WHERE nombre='A1'),now(),1,1000,250,'medido');
INSERT INTO aforos(finca_id,unidad_id,fecha_aforo,materia_fresca_g,naturaleza) VALUES (:F,(SELECT id FROM unidades_espaciales WHERE nombre='A2'),now(),800,'medido');
SELECT 'T %MS = 25.00 calculado' t, ms_pct_calculado=25.00 AND estado_ms_pct='calculado' AND ms_g_por_m2_calculado=250 ok FROM v_aforos_calculo WHERE ms_pct_calculado IS NOT NULL;
SELECT 'T sin MS => no calculable (NULL, no 0)' t, ms_pct_calculado IS NULL AND estado_ms_pct='no_calculable' ok FROM v_aforos_calculo WHERE ms_pct_calculado IS NULL;
DO $$ BEGIN INSERT INTO aforos(finca_id,unidad_id,fecha_aforo,materia_fresca_g,materia_seca_g,naturaleza) VALUES ('aaaaaaaa-0000-0000-0000-000000000001',(SELECT id FROM unidades_espaciales WHERE nombre='A3'),now(),100,300,'medido'); RAISE NOTICE 'FALLA: MS > MF'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK MS mayor que MF rechazado'; END $$;
DO $$ BEGIN INSERT INTO aforos(finca_id,unidad_id,fecha_aforo) VALUES ('aaaaaaaa-0000-0000-0000-000000000001',(SELECT id FROM unidades_espaciales WHERE nombre='A3'),now()); RAISE NOTICE 'FALLA: aforo sin naturaleza'; EXCEPTION WHEN not_null_violation THEN RAISE NOTICE 'OK aforo exige naturaleza'; END $$;
RESET ROLE; SET ROLE authenticated; SET request.jwt.claim.sub='22222222-2222-2222-2222-222222222222';
SELECT 'T no miembro no ve alertas ni aforos ni destinos' t, (SELECT count(*) FROM v_alertas_ocupacion)=0 AND (SELECT count(*) FROM v_aforos_calculo)=0 AND (SELECT count(*) FROM destinos_superficie)=0 ok;
RESET ROLE;
SELECT 'T auditoría pasturas' t, count(*)=6 ok FROM auditoria WHERE tabla_afectada IN ('ocupaciones_pastoreo','aforos','destinos_superficie');
