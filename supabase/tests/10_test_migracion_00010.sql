\pset pager off
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
INSERT INTO guias(id,finca_id,codigo,titulo) VALUES ('eeeeeeee-0000-0000-0000-0000000000a1','aaaaaaaa-0000-0000-0000-000000000001','G-10','Guía de prueba 00010');
INSERT INTO guia_versiones(id,finca_id,guia_id,numero,que_es,para_que,por_que,donde,como,metodo,materiales,unidades,pasos,precauciones,errores_comunes,prohibiciones,registro,evidencia,validacion,seguimiento,fuente,revisado_por)
 VALUES ('ffffffff-0000-0000-0000-0000000000a1','aaaaaaaa-0000-0000-0000-000000000001','eeeeeeee-0000-0000-0000-0000000000a1',1,'t','t','t','t','t','t','t','t','t','t','t','t','t','t','t','t','fuente prueba','11111111-1111-1111-1111-111111111111');
DO $$ BEGIN UPDATE guia_versiones SET estado='publicada' WHERE id='ffffffff-0000-0000-0000-0000000000a1'; RAISE NOTICE 'FALLA: publicó sin los 6 campos nuevos'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK publicar exige cuándo, quién, equipos, preparación, suspensión y aceptación: %', SQLERRM; END $$;
UPDATE guia_versiones SET cuando='t',quien_puede='t',equipos='t',preparacion='t',condiciones_suspension=' ',criterios_aceptacion='t' WHERE id='ffffffff-0000-0000-0000-0000000000a1';
DO $$ BEGIN UPDATE guia_versiones SET estado='publicada' WHERE id='ffffffff-0000-0000-0000-0000000000a1'; RAISE NOTICE 'FALLA: aceptó vacío'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK un campo vacío no se acepta (debe decir "no aplica")'; END $$;
UPDATE guia_versiones SET condiciones_suspension='no aplica' WHERE id='ffffffff-0000-0000-0000-0000000000a1';
UPDATE guia_versiones SET estado='publicada' WHERE id='ffffffff-0000-0000-0000-0000000000a1';
SELECT 'T publicada con los 22 elementos' t, estado='publicada' AND publicada_en IS NOT NULL ok FROM guia_versiones WHERE id='ffffffff-0000-0000-0000-0000000000a1';
DO $$ BEGIN UPDATE guia_versiones SET equipos='cambiado' WHERE id='ffffffff-0000-0000-0000-0000000000a1'; RAISE NOTICE 'FALLA: editó publicada'; EXCEPTION WHEN restrict_violation THEN RAISE NOTICE 'OK publicada sigue inmutable (campos nuevos incluidos)'; END $$;
