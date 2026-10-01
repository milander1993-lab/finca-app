\pset pager off
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
\set F '''aaaaaaaa-0000-0000-0000-000000000001'''
-- aforo con 3 puntos (potrero P4), el 3.º aún sin secar
INSERT INTO aforos(id,finca_id,unidad_id,fecha_aforo,naturaleza) VALUES ('99999999-0000-0000-0000-000000000001',:F,(SELECT id FROM unidades_espaciales WHERE nombre='P4'),now(),'medido');
SELECT 'T aforo sin puntos => no calculable (no 0)' t, estado_ms_pct='no_calculable' AND ms_pct IS NULL AND agua_pct IS NULL ok FROM v_aforos_resumen WHERE aforo_id='99999999-0000-0000-0000-000000000001';
INSERT INTO aforo_muestras(finca_id,aforo_id,punto,area_muestra_m2,materia_fresca_g,materia_seca_g) VALUES
 (:F,'99999999-0000-0000-0000-000000000001',1,1,1000,250),
 (:F,'99999999-0000-0000-0000-000000000001',2,1,800,200),
 (:F,'99999999-0000-0000-0000-000000000001',3,1,1200,NULL);
SELECT 'T 2 de 3 puntos con MS: %MS=25.00, agua=75.00, advierte' t, n_puntos=3 AND n_puntos_con_ms=2 AND ms_pct=25.00 AND agua_pct=75.00 AND advertencia IS NOT NULL ok FROM v_aforos_resumen WHERE aforo_id='99999999-0000-0000-0000-000000000001';
UPDATE aforo_muestras SET materia_seca_g=320 WHERE punto=3;
-- ΣMS=770, ΣMF=3000 => 25.67 ; agua 74.33 ; 770/3=256.67 g/m2 ; 2566.7 kg/ha
SELECT 'T 3 puntos: %MS=25.67 agua=74.33' t, ms_pct=25.67 AND agua_pct=74.33 AND advertencia IS NULL ok FROM v_aforos_resumen WHERE aforo_id='99999999-0000-0000-0000-000000000001';
SELECT 'T MS por m2 = 256.67 y kg MS/ha = 2566.7' t, ms_g_por_m2=256.67 AND ms_kg_por_ha=2566.7 ok FROM v_aforos_resumen WHERE aforo_id='99999999-0000-0000-0000-000000000001';
SELECT 'T variabilidad entre puntos (25.00 a 26.67)' t, ms_pct_min_punto=25.00 AND ms_pct_max_punto=26.67 ok FROM v_aforos_resumen WHERE aforo_id='99999999-0000-0000-0000-000000000001';
-- aforo antiguo de un solo punto (cabecera) sigue funcionando + agua
SELECT 'T aforo antiguo de cabecera: 25% MS, 75% agua' t, ms_pct=25.00 AND agua_pct=75.00 AND n_puntos=1 ok FROM v_aforos_resumen WHERE unidad_id=(SELECT id FROM unidades_espaciales WHERE nombre='A1') AND ms_pct IS NOT NULL;
SELECT 'T v_aforos_calculo trae agua 75.00' t, agua_pct_calculado=75.00 ok FROM v_aforos_calculo WHERE ms_pct_calculado=25.00 LIMIT 1;
-- reglas
DO $$ BEGIN INSERT INTO aforo_muestras(finca_id,aforo_id,punto,materia_fresca_g,materia_seca_g) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','99999999-0000-0000-0000-000000000001',4,100,300); RAISE NOTICE 'FALLA: MS > MF'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK MS no puede superar MF'; END $$;
DO $$ BEGIN INSERT INTO aforo_muestras(finca_id,aforo_id,punto,materia_fresca_g) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','99999999-0000-0000-0000-000000000001',1,100); RAISE NOTICE 'FALLA: punto duplicado'; EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK punto único por aforo'; END $$;
DO $$ BEGIN INSERT INTO aforo_muestras(finca_id,aforo_id,punto,materia_fresca_g) VALUES ('aaaaaaaa-0000-0000-0000-000000000002','99999999-0000-0000-0000-000000000001',9,100); RAISE NOTICE 'FALLA: finca distinta'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK punto de otra finca rechazado'; END $$;
DO $$ BEGIN UPDATE aforo_muestras SET materia_fresca_g=5 WHERE punto=1; RAISE NOTICE 'FALLA: reescribió MF'; EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'OK peso fresco no se reescribe'; END $$;
DO $$ BEGIN UPDATE aforo_muestras SET materia_seca_g=1 WHERE punto=1; RAISE NOTICE 'FALLA: reescribió MS'; EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'OK MS registrada no se reescribe'; END $$;
DO $$ BEGIN DELETE FROM aforo_muestras; RAISE NOTICE 'FALLA delete'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK delete bloqueado'; END $$;
-- punto marcado inconsistente no entra al cálculo (y no se borra)
UPDATE aforo_muestras SET estado_calidad='inconsistente', nota_calidad='posible inconsistencia: secado incompleto' WHERE punto=3;
SELECT 'T punto inconsistente excluido, sigue existiendo' t, ms_pct=25.00 AND n_puntos=2 ok FROM v_aforos_resumen WHERE aforo_id='99999999-0000-0000-0000-000000000001';
SELECT 'T el punto sigue guardado' t, count(*)=3 ok FROM aforo_muestras WHERE aforo_id='99999999-0000-0000-0000-000000000001';
RESET ROLE; SET ROLE authenticated; SET request.jwt.claim.sub='22222222-2222-2222-2222-222222222222';
SELECT 'T no miembro no ve muestras ni resumen' t, (SELECT count(*) FROM aforo_muestras)=0 AND (SELECT count(*) FROM v_aforos_resumen)=0 ok;
RESET ROLE;
SELECT 'T auditoría de muestras' t, count(*)>=4 ok FROM auditoria WHERE tabla_afectada='aforo_muestras';
