\pset pager off
-- preparación (superusuario): lote y 3 animales nuevos
INSERT INTO animales(id,finca_id,numero_interno,categoria,estado) VALUES
 ('cccccccc-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','M-001','vaca','activo'),
 ('cccccccc-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','M-002','vaca','activo'),
 ('cccccccc-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001','M-003','vaca','activo');
INSERT INTO lotes_ganaderos(id,finca_id,nombre) VALUES ('eeeeeeee-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','LoteCalc'),('eeeeeeee-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','LoteVacio');
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
\set F '''aaaaaaaa-0000-0000-0000-000000000001'''
\set L '''eeeeeeee-0000-0000-0000-000000000001'''
INSERT INTO animal_lote(finca_id,animal_id,lote_id,fecha_ingreso) SELECT :F,id,:L,now()-interval '60 days' FROM animales WHERE numero_interno IN ('M-001','M-002','M-003');
-- 1. sin criterio => no calculable
SELECT 'T sin criterio => no_calculable (no 0)' t, resultado='no_calculable' AND valor IS NULL AND faltantes::text LIKE '%criterio_ms_pct_peso_vivo%' ok FROM calcular_demanda_ms_lote('aaaaaaaa-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001');
-- 2. criterio exige fuente y rango
DO $$ BEGIN INSERT INTO criterios_parametros(finca_id,codigo,nombre,valor,unidad,fuente) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','ms_pct_peso_vivo','x',250,'% peso vivo/día','prueba'); RAISE NOTICE 'FALLA: pct>100'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK pct >100 rechazado'; END $$;
DO $$ BEGIN INSERT INTO criterios_parametros(finca_id,codigo,nombre,valor,unidad,fuente) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','ms_pct_peso_vivo','x',2.5,'% peso vivo/día',' '); RAISE NOTICE 'FALLA: sin fuente'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK criterio exige fuente'; END $$;
INSERT INTO criterios_parametros(finca_id,codigo,nombre,valor,unidad,fuente,vigente_desde) VALUES (:F,'ms_pct_peso_vivo','Consumo MS % PV',2.5,'% peso vivo/día','valor de prueba (no real)',now()-interval '30 days');
-- 3. falta peso de animales => no calculable, lista faltantes
SELECT 'T animales sin peso => no_calculable' t, resultado='no_calculable' AND jsonb_array_length(faltantes)=3 ok FROM calcular_demanda_ms_lote('aaaaaaaa-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001');
INSERT INTO pesajes(finca_id,animal_id,fecha_pesaje,valor,naturaleza) VALUES
 (:F,'cccccccc-0000-0000-0000-000000000001',now()-interval '5 days',400,'medido'),
 (:F,'cccccccc-0000-0000-0000-000000000002',now()-interval '5 days',300,'estimado');
SELECT 'T falta un peso => no_calculable (sin cálculo parcial)' t, resultado='no_calculable' AND jsonb_array_length(faltantes)=1 AND valor IS NULL ok FROM calcular_demanda_ms_lote('aaaaaaaa-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001');
INSERT INTO pesajes(finca_id,animal_id,fecha_pesaje,valor,naturaleza) VALUES (:F,'cccccccc-0000-0000-0000-000000000003',now()-interval '5 days',200,'medido');
-- 4. cálculo correcto: (400+300+200) * 2.5 / 100 = 22.5
SELECT 'T demanda = 22.5 kg MS/día' t, resultado='calculado' AND valor=22.5 AND unidad='kg MS/día' AND naturaleza='calculado' ok FROM calcular_demanda_ms_lote('aaaaaaaa-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001');
SELECT 'T hereda incertidumbre por peso estimado' t, incertidumbre LIKE '%no medidos%' AND (entradas->>'peso_total_kg')::numeric=900 ok FROM calculos WHERE resultado='calculado' ORDER BY created_at DESC LIMIT 1;
SELECT 'T guarda fórmula, versión, criterio, usuario' t, version_formula='demanda_ms_lote.v1' AND formula LIKE '%pct%' AND parametro_id IS NOT NULL AND calculado_por='11111111-1111-1111-1111-111111111111' ok FROM calculos WHERE resultado='calculado' ORDER BY created_at DESC LIMIT 1;
-- 5. criterio nuevo NO reinterpreta histórico
INSERT INTO criterios_parametros(finca_id,codigo,nombre,valor,unidad,fuente,vigente_desde) VALUES (:F,'ms_pct_peso_vivo','Consumo MS % PV',3,'% peso vivo/día','valor de prueba 2',now()-interval '1 day');
SELECT 'T con criterio nuevo = 27' t, valor=27 ok FROM calcular_demanda_ms_lote('aaaaaaaa-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001');
SELECT 'T a fecha anterior sigue usando el criterio viejo (22.5)' t, valor=22.5 ok FROM calcular_demanda_ms_lote('aaaaaaaa-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001', now()-interval '3 days');
SELECT 'T resultado anterior intacto' t, count(*)=2 ok FROM calculos WHERE valor=22.5;
-- 6. pesaje rechazado no se usa
UPDATE pesajes SET estado_calidad='rechazado', nota_calidad='pesaje dudoso' WHERE valor=200;
SELECT 'T pesaje rechazado => animal queda sin peso => no_calculable' t, resultado='no_calculable' ok FROM calcular_demanda_ms_lote('aaaaaaaa-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001');
-- 7. lote vacío
SELECT 'T lote sin animales => no_calculable (no 0)' t, resultado='no_calculable' AND valor IS NULL AND faltantes::text LIKE '%lote_sin_animales%' ok FROM calcular_demanda_ms_lote('aaaaaaaa-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000002');
-- 8. inmutabilidad y acceso
DO $$ BEGIN UPDATE calculos SET valor=1 WHERE resultado='calculado'; RAISE NOTICE 'FALLA: reescribió cálculo'; EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'OK un cálculo no se reescribe'; END $$;
DO $$ BEGIN UPDATE criterios_parametros SET valor=9; RAISE NOTICE 'FALLA: reescribió criterio'; EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'OK un criterio no se reescribe (nueva versión)'; END $$;
DO $$ BEGIN DELETE FROM calculos; RAISE NOTICE 'FALLA delete'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK delete bloqueado'; END $$;
DO $$ BEGIN PERFORM calcular_demanda_ms_lote('aaaaaaaa-0000-0000-0000-000000000002','eeeeeeee-0000-0000-0000-000000000001'); RAISE NOTICE 'FALLA: finca ajena'; EXCEPTION WHEN insufficient_privilege THEN RAISE NOTICE 'OK finca ajena bloqueada'; END $$;
UPDATE calculos SET is_deleted=true WHERE id=(SELECT id FROM calculos ORDER BY created_at LIMIT 1);
SELECT 'T anular sí se permite (historia queda)' t, count(*)>=1 ok FROM calculos WHERE is_deleted;
