\pset pager off
INSERT INTO auth.users(id,email) VALUES ('33333333-3333-3333-3333-333333333333','nuevo@t') ON CONFLICT DO NOTHING;
SET ROLE authenticated; SET request.jwt.claim.sub='33333333-3333-3333-3333-333333333333';
SELECT 'T usuario nuevo no ve fincas' t, count(*)=0 ok FROM fincas;
DO $$ BEGIN PERFORM crear_finca_inicial('  '); RAISE NOTICE 'FALLA: nombre vacío'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK nombre de finca obligatorio'; END $$;
SELECT crear_finca_inicial('Mi Finca') IS NOT NULL AS creada;
SELECT 'T crea su finca y la ve (miembro)' t, count(*)=1 ok FROM fincas WHERE nombre='Mi Finca';
DO $$ BEGIN PERFORM crear_finca_inicial('Otra'); RAISE NOTICE 'FALLA: segunda finca'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK no crea otra si ya pertenece a una'; END $$;
-- el miembro opera desde la app (inserciones con RLS)
INSERT INTO animales(id,finca_id,numero_interno,categoria,estado) SELECT '44444444-0000-0000-0000-000000000001',id,'N-1','vaca','activo' FROM fincas WHERE nombre='Mi Finca';
INSERT INTO lotes_ganaderos(id,finca_id,nombre) SELECT '55555555-0000-0000-0000-000000000001',id,'L-A' FROM fincas WHERE nombre='Mi Finca';
INSERT INTO lotes_ganaderos(id,finca_id,nombre) SELECT '55555555-0000-0000-0000-000000000002',id,'L-B' FROM fincas WHERE nombre='Mi Finca';
SELECT 'T miembro crea animal y lotes' t, (SELECT count(*) FROM animales WHERE numero_interno='N-1')=1 AND (SELECT count(*) FROM lotes_ganaderos WHERE nombre LIKE 'L-%')=2 ok;
DO $$ DECLARE f uuid; BEGIN SELECT id INTO f FROM fincas WHERE nombre='Mi Finca'; PERFORM mover_animal_lote(f,'44444444-0000-0000-0000-000000000001','55555555-0000-0000-0000-000000000001',now()-interval '2 days',' '); RAISE NOTICE 'FALLA: sin motivo'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK mover exige motivo'; END $$;
SELECT mover_animal_lote((SELECT id FROM fincas WHERE nombre='Mi Finca'),'44444444-0000-0000-0000-000000000001','55555555-0000-0000-0000-000000000001',now()-interval '2 days','ingreso inicial') IS NOT NULL AS m1;
SELECT mover_animal_lote((SELECT id FROM fincas WHERE nombre='Mi Finca'),'44444444-0000-0000-0000-000000000001','55555555-0000-0000-0000-000000000002',now()-interval '1 day','cambio de lote') IS NOT NULL AS m2;
SELECT 'T historial: 2 pertenencias, 1 abierta en L-B, la anterior cerrada con motivo' t,
  (SELECT count(*) FROM animal_lote WHERE animal_id='44444444-0000-0000-0000-000000000001')=2
  AND (SELECT lote_id FROM animal_lote WHERE animal_id='44444444-0000-0000-0000-000000000001' AND fecha_salida IS NULL)='55555555-0000-0000-0000-000000000002'
  AND (SELECT motivo_salida FROM animal_lote WHERE lote_id='55555555-0000-0000-0000-000000000001')='cambio de lote' ok;
DO $$ DECLARE f uuid; BEGIN SELECT id INTO f FROM fincas WHERE nombre='Mi Finca'; PERFORM mover_animal_lote(f,'44444444-0000-0000-0000-000000000001','55555555-0000-0000-0000-000000000002',now(),'x'); RAISE NOTICE 'FALLA: mismo lote'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK no mueve al mismo lote'; END $$;
DO $$ BEGIN PERFORM mover_animal_lote('aaaaaaaa-0000-0000-0000-000000000001','44444444-0000-0000-0000-000000000001','55555555-0000-0000-0000-000000000001',now(),'x'); RAISE NOTICE 'FALLA: finca ajena'; EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK finca ajena bloqueada'; END $$;
RESET ROLE;
