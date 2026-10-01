\pset pager off
INSERT INTO lotes_ganaderos(id,finca_id,nombre) VALUES ('dddddddd-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','Lote A'),('dddddddd-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','Lote B'),('dddddddd-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-000000000002','Lote ajeno');
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
INSERT INTO animal_lote(finca_id,animal_id,lote_id,fecha_ingreso) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000001',now()-interval '5 days');
DO $$ BEGIN INSERT INTO animal_lote(finca_id,animal_id,lote_id,fecha_ingreso) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000002',now()); RAISE NOTICE 'FALLA: dos lotes abiertos'; EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK un solo lote abierto'; END $$;
DO $$ BEGIN INSERT INTO animal_lote(finca_id,animal_id,lote_id,fecha_ingreso) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002','dddddddd-0000-0000-0000-000000000009',now()); RAISE NOTICE 'FALLA: lote ajeno'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK lote de otra finca rechazado'; END $$;
DO $$ BEGIN UPDATE animal_lote SET fecha_salida=now(); RAISE NOTICE 'FALLA: cerró sin motivo'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK cierre sin motivo rechazado'; END $$;
DO $$ BEGIN UPDATE animal_lote SET lote_id='dddddddd-0000-0000-0000-000000000002'; RAISE NOTICE 'FALLA: reescribió'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK reescritura rechazada'; END $$;
UPDATE animal_lote SET fecha_salida=now(), motivo_salida='traslado' WHERE motivo_salida IS NULL;
INSERT INTO animal_lote(finca_id,animal_id,lote_id,fecha_ingreso) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001','dddddddd-0000-0000-0000-000000000002',now());
SELECT 'T historia: 2 filas, 1 abierta' t, count(*)=2 AND count(*) FILTER (WHERE fecha_salida IS NULL)=1 ok FROM animal_lote;
DO $$ BEGIN DELETE FROM animal_lote; RAISE NOTICE 'FALLA delete'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK delete bloqueado'; END $$;
RESET ROLE;
SET ROLE authenticated; SET request.jwt.claim.sub='22222222-2222-2222-2222-222222222222';
SELECT 'T no miembro no ve lotes' t, count(*)=0 ok FROM lotes_ganaderos;
RESET ROLE;
SELECT 'T auditoría de animal_lote' t, count(*)>=3 ok FROM auditoria WHERE tabla_afectada='animal_lote';
