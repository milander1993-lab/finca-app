\pset pager off
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
\set F '''aaaaaaaa-0000-0000-0000-000000000001'''
CREATE OR REPLACE FUNCTION pg_temp.op(p_op text,p_cod text,p_animal uuid,p_motivo text,p_esp text) RETURNS text LANGUAGE plpgsql AS $f$ DECLARE v text; BEGIN
 INSERT INTO qr_operaciones(finca_id,codigo,operacion,animal_id,motivo,estado_esperado,creada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000001',p_cod,p_op,p_animal,p_motivo,p_esp,now()) RETURNING estado||':'||coalesce(resultado_detalle->>'codigo_error','ok') INTO v; RETURN v; END $f$;
-- 1. QR con operaciones pendientes
SELECT 'T registrar QR8' t, pg_temp.op('registrar','QR8',null,null,null)='aplicada:ok' ok;
SELECT 'T operación con vista vieja => conflicto pendiente' t, pg_temp.op('asignar','QR8','bbbbbbbb-0000-0000-0000-000000000001',null,'liberado')='conflicto:estado_divergente' ok;
SELECT 'T no reasigna con operación pendiente' t, pg_temp.op('asignar','QR8','bbbbbbbb-0000-0000-0000-000000000001',null,null)='rechazada:operaciones_pendientes' ok;
SELECT 'T el QR sigue disponible (no se aplicó)' t, estado='disponible' ok FROM codigos_qr WHERE codigo='QR8';
SELECT qr_revisar_operacion((SELECT id FROM qr_operaciones WHERE codigo='QR8' AND estado='conflicto'),'revisado en prueba');
SELECT 'T tras revisar, sí reasigna' t, pg_temp.op('asignar','QR8','bbbbbbbb-0000-0000-0000-000000000001',null,'disponible')='aplicada:ok' ok;
-- 2. evidencia identificacion
INSERT INTO evidencias_animal(finca_id,animal_id,tipo,tomada_en,naturaleza) VALUES (:F,'bbbbbbbb-0000-0000-0000-000000000002','identificacion',now(),'observado');
SELECT 'T tipo identificacion aceptado' t, count(*)=1 ok FROM evidencias_animal WHERE tipo='identificacion';
DO $$ BEGIN INSERT INTO evidencias_animal(finca_id,animal_id,tipo,tomada_en,naturaleza) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000002','otro',now(),'observado'); RAISE NOTICE 'FALLA: tipo inventado'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK tipo desconocido rechazado'; END $$;
-- 3. calidad de datos
SELECT 'T estado_calidad por defecto = registrado' t, estado_calidad='registrado' ok FROM pesajes LIMIT 1;
DO $$ BEGIN UPDATE pesajes SET estado_calidad='inconsistente' WHERE id=(SELECT id FROM pesajes LIMIT 1); RAISE NOTICE 'FALLA: inconsistente sin nota'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK inconsistente exige nota'; END $$;
UPDATE pesajes SET estado_calidad='inconsistente', nota_calidad='posible inconsistencia con pesaje previo' WHERE id=(SELECT id FROM pesajes ORDER BY created_at LIMIT 1);
SELECT 'T marcado inconsistente y NO borrado' t, count(*)=1 ok FROM pesajes WHERE estado_calidad='inconsistente' AND NOT is_deleted;
DO $$ BEGIN UPDATE pesajes SET estado_calidad='validado' WHERE estado_calidad='registrado'; RAISE NOTICE 'FALLA: validado sin validador'; EXCEPTION WHEN check_violation THEN RAISE NOTICE 'OK validar exige validador'; END $$;
DO $$ BEGIN UPDATE pesajes SET estado_calidad='cualquiera'; RAISE NOTICE 'FALLA: estado invalido'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK estado de calidad invalido rechazado'; END $$;
-- 4. fecha de sincronización
INSERT INTO pesajes(finca_id,animal_id,fecha_pesaje,valor,naturaleza,sincronizada_en) VALUES (:F,'bbbbbbbb-0000-0000-0000-000000000001',now()-interval '30 days',250,'medido','2000-01-01');
SELECT 'T sincronizada_en la pone el servidor' t, sincronizada_en IS NOT NULL ok FROM pesajes WHERE valor=250;
SELECT 'T cliente no falsifica sincronizada_en' t, sincronizada_en > now()-interval '1 minute' ok FROM pesajes WHERE valor=250;
DO $$ DECLARE a timestamptz; b timestamptz; BEGIN SELECT sincronizada_en INTO a FROM pesajes WHERE valor=250; UPDATE pesajes SET sincronizada_en='2001-01-01', observaciones='x' WHERE valor=250; SELECT sincronizada_en INTO b FROM pesajes WHERE valor=250; IF a=b THEN RAISE NOTICE 'OK sincronizada_en no cambia en update'; ELSE RAISE NOTICE 'FALLA: cambió sincronizada_en'; END IF; END $$;
SELECT 'T fecha del hecho distinta de la de registro' t, fecha_pesaje < created_at - interval '29 days' ok FROM pesajes WHERE valor=250;
