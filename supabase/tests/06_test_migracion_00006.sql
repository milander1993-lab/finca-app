\pset pager off
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
INSERT INTO guias(id,finca_id,codigo,titulo) VALUES ('eeeeeeee-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','G-TEST','Guía de prueba (estructura)');
DO $$ BEGIN INSERT INTO guias(finca_id,codigo,titulo) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','g-test','dup'); RAISE NOTICE 'FALLA: código duplicado'; EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK código de guía único (sin distinguir mayúsculas)'; END $$;
INSERT INTO guia_versiones(id,finca_id,guia_id,numero) VALUES ('ffffffff-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001',1);
SELECT 'T borrador nace vacío (no se rellena nada)' t, que_es IS NULL AND estado='borrador' ok FROM guia_versiones;
DO $$ BEGIN UPDATE guia_versiones SET estado='publicada'; RAISE NOTICE 'FALLA: publicó incompleta'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK no se publica guía incompleta'; END $$;
-- datos de PRUEBA con texto marcador, no contenido técnico real
UPDATE guia_versiones SET que_es='x',para_que='x',por_que='x',donde='x',como='x',metodo='x',materiales='x',unidades='x',pasos='x',precauciones='x',errores_comunes='x',prohibiciones='x',registro='x',evidencia='x',validacion='x',seguimiento='x';
DO $$ BEGIN UPDATE guia_versiones SET estado='publicada',fuente='x'; RAISE NOTICE 'FALLA: publicó sin revisor'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK publicar exige revisor'; END $$;
DO $$ BEGIN UPDATE guia_versiones SET estado='publicada',revisado_por='11111111-1111-1111-1111-111111111111'; RAISE NOTICE 'FALLA: publicó sin fuente'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK publicar exige fuente'; END $$;
UPDATE guia_versiones SET estado='publicada',fuente='fuente de prueba',revisado_por='11111111-1111-1111-1111-111111111111';
SELECT 'T publicada con fecha' t, estado='publicada' AND publicada_en IS NOT NULL ok FROM guia_versiones;
DO $$ BEGIN UPDATE guia_versiones SET como='cambiado'; RAISE NOTICE 'FALLA: editó publicada'; EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'OK publicada no se edita'; END $$;
-- versión 2: la 1 pasa a reemplazada al publicar la 2
INSERT INTO guia_versiones(id,finca_id,guia_id,numero,que_es,para_que,por_que,donde,como,metodo,materiales,unidades,pasos,precauciones,errores_comunes,prohibiciones,registro,evidencia,validacion,seguimiento,fuente,revisado_por)
 VALUES ('ffffffff-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-000000000001',2,'y','y','y','y','y','y','y','y','y','y','y','y','y','y','y','y','fuente2','11111111-1111-1111-1111-111111111111');
UPDATE guia_versiones SET estado='publicada' WHERE numero=2;
SELECT 'T al publicar v2, v1 queda reemplazada y hay 1 publicada' t, (SELECT estado FROM guia_versiones WHERE numero=1)='reemplazada' AND (SELECT count(*) FROM guia_versiones WHERE estado='publicada')=1 ok;
DO $$ BEGIN UPDATE guia_versiones SET estado='publicada' WHERE numero=1; RAISE NOTICE 'FALLA: resucitó reemplazada'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK una reemplazada no vuelve a publicarse'; END $$;
DO $$ BEGIN DELETE FROM guia_versiones; RAISE NOTICE 'FALLA delete'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK delete bloqueado'; END $$;
RESET ROLE; SET ROLE authenticated; SET request.jwt.claim.sub='22222222-2222-2222-2222-222222222222';
SELECT 'T no miembro no ve guías' t, count(*)=0 ok FROM guias;
RESET ROLE;
SELECT 'T auditoría de guías' t, count(*)>=5 ok FROM auditoria WHERE tabla_afectada IN ('guias','guia_versiones');
