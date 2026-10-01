\pset pager off
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
INSERT INTO evidencias_animal(finca_id,animal_id,tipo,tomada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','principal',now()-interval '1 hour');
SELECT 'T nace pendiente_sincronizacion y observado' t, estado_subida='pendiente_sincronizacion' AND naturaleza='observado' ok FROM evidencias_animal;
DO $$ BEGIN INSERT INTO evidencias_animal(finca_id,animal_id,tipo,tomada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','principal',now()); RAISE NOTICE 'FALLA: 2 principales'; EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK una sola principal vigente'; END $$;
DO $$ BEGIN INSERT INTO evidencias_animal(finca_id,animal_id,tipo,tomada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','perfil_inventado',now()); RAISE NOTICE 'FALLA: tipo inventado'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK tipo no aprobado rechazado'; END $$;
DO $$ BEGIN INSERT INTO evidencias_animal(finca_id,animal_id,tipo,tomada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000009','serie_corporal',now()); RAISE NOTICE 'FALLA: animal ajeno'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK animal de otra finca rechazado'; END $$;
DO $$ BEGIN INSERT INTO evidencias_animal(finca_id,animal_id,tipo,angulo,tomada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','ubre','lateral',now()); RAISE NOTICE 'FALLA: angulo en ubre'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK ángulo solo en serie corporal'; END $$;
DO $$ BEGIN UPDATE evidencias_animal SET estado_subida='subida'; RAISE NOTICE 'FALLA: subida sin drive_file_id'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK subida exige drive_file_id'; END $$;
DO $$ BEGIN UPDATE evidencias_animal SET tipo='ubre'; RAISE NOTICE 'FALLA: reescribió tipo'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK reescritura rechazada'; END $$;
UPDATE evidencias_animal SET estado_subida='subida', drive_file_id='drv123', sha256=repeat('a',64), bytes=1000;
DO $$ BEGIN UPDATE evidencias_animal SET drive_file_id='otro'; RAISE NOTICE 'FALLA: cambió archivo subido'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK archivo subido inmutable'; END $$;
DO $$ BEGIN DELETE FROM evidencias_animal; RAISE NOTICE 'FALLA delete'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK delete bloqueado'; END $$;
-- anular la principal permite registrar otra
UPDATE evidencias_animal SET is_deleted=true;
INSERT INTO evidencias_animal(finca_id,animal_id,tipo,tomada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','principal',now());
SELECT 'T anular y reemplazar principal' t, count(*)=2 AND count(*) FILTER (WHERE NOT is_deleted)=1 ok FROM evidencias_animal;
RESET ROLE; SET ROLE authenticated; SET request.jwt.claim.sub='22222222-2222-2222-2222-222222222222';
SELECT 'T no miembro no ve evidencias' t, count(*)=0 ok FROM evidencias_animal;
RESET ROLE;
SELECT 'T auditoría evidencias' t, count(*)>=4 ok FROM auditoria WHERE tabla_afectada='evidencias_animal';
