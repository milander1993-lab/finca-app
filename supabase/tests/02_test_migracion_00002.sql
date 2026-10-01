\set ON_ERROR_STOP off
\pset pager off
-- datos
INSERT INTO auth.users(id,email) VALUES ('11111111-1111-1111-1111-111111111111','u1@t'),('22222222-2222-2222-2222-222222222222','u2@t');
INSERT INTO fincas(id,nombre) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','F1'),('aaaaaaaa-0000-0000-0000-000000000002','F2');
INSERT INTO finca_miembros(finca_id,user_id) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','11111111-1111-1111-1111-111111111111');
INSERT INTO animales(id,finca_id,numero_interno,categoria,estado) VALUES
 ('bbbbbbbb-0000-0000-0000-000000000001','aaaaaaaa-0000-0000-0000-000000000001','A-001','vaca','activo'),
 ('bbbbbbbb-0000-0000-0000-000000000002','aaaaaaaa-0000-0000-0000-000000000001','A-002','vaca','activo'),
 ('bbbbbbbb-0000-0000-0000-000000000003','aaaaaaaa-0000-0000-0000-000000000001','A-003','vaca','vendido'),
 ('bbbbbbbb-0000-0000-0000-000000000009','aaaaaaaa-0000-0000-0000-000000000002','X-001','vaca','activo');
SELECT 'T0 peso inicial es NULL (N/A, no 0)' t, peso_ultimo IS NULL ok FROM animales WHERE numero_interno='A-001';

-- Operaciones como u1 (cliente)
SET ROLE authenticated; SET request.jwt.claim.sub='11111111-1111-1111-1111-111111111111';
CREATE TEMP TABLE r(n text, esp text, got text);
GRANT ALL ON r TO PUBLIC;
CREATE OR REPLACE FUNCTION pg_temp.op(p_op text, p_cod text, p_animal uuid, p_motivo text, p_esp text, p_finca uuid default 'aaaaaaaa-0000-0000-0000-000000000001') RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v text; BEGIN
 INSERT INTO qr_operaciones(finca_id,codigo,operacion,animal_id,motivo,estado_esperado,creada_en) VALUES (p_finca,p_cod,p_op,p_animal,p_motivo,p_esp,now()) RETURNING estado||':'||coalesce(resultado_detalle->>'codigo_error',resultado_detalle->>'mensaje','ok') INTO v; RETURN v; END $f$;
INSERT INTO r SELECT 'registrar QR1','aplicada:ok',pg_temp.op('registrar','QR1',null,null,null);
INSERT INTO r SELECT 'registrar QR1 duplicado','rechazada:codigo_existente',pg_temp.op('registrar','QR1',null,null,null);
INSERT INTO r SELECT 'registrar QR2','aplicada:ok',pg_temp.op('registrar','QR2',null,null,null);
INSERT INTO r SELECT 'asignar QR1->A1','aplicada:ok',pg_temp.op('asignar','QR1','bbbbbbbb-0000-0000-0000-000000000001','collar nuevo','disponible');
INSERT INTO r SELECT 'asignar QR1->A2 (QR ocupado, vista vieja)','conflicto:estado_divergente',left(pg_temp.op('asignar','QR1','bbbbbbbb-0000-0000-0000-000000000002',null,'disponible'),36);
INSERT INTO r SELECT 'asignar QR1->A2 (sin estado_esperado)','rechazada:qr_no_disponible',pg_temp.op('asignar','QR1','bbbbbbbb-0000-0000-0000-000000000002',null,null);
INSERT INTO r SELECT 'asignar QR2->A1 (animal ya tiene QR)','rechazada:animal_con_qr',left(pg_temp.op('asignar','QR2','bbbbbbbb-0000-0000-0000-000000000001',null,'disponible'),29);
INSERT INTO r SELECT 'asignar QR2->A3 (animal vendido)','rechazada:animal_no_activo',pg_temp.op('asignar','QR2','bbbbbbbb-0000-0000-0000-000000000003',null,'disponible');
INSERT INTO r SELECT 'asignar QR2->animal de otra finca','rechazada:animal_no_encontrado',pg_temp.op('asignar','QR2','bbbbbbbb-0000-0000-0000-000000000009',null,'disponible');
INSERT INTO r SELECT 'operar en finca ajena','ERROR',coalesce((SELECT 'x' WHERE false),'ERROR_PENDIENTE');
INSERT INTO r SELECT 'confirmar QR1','aplicada:ok',pg_temp.op('confirmar','QR1','bbbbbbbb-0000-0000-0000-000000000001',null,'asignado');
INSERT INTO r SELECT 'confirmar QR1 otra vez (idempotente)','conflicto:estado_divergente',left(pg_temp.op('confirmar','QR1','bbbbbbbb-0000-0000-0000-000000000001',null,'asignado'),36);
INSERT INTO r SELECT 'liberar sin motivo','rechazada:motivo_requerido',pg_temp.op('liberar','QR1','bbbbbbbb-0000-0000-0000-000000000001',null,'activo');
INSERT INTO r SELECT 'liberar con animal equivocado','conflicto:animal_divergente',left(pg_temp.op('liberar','QR1','bbbbbbbb-0000-0000-0000-000000000002','x','activo'),35);
INSERT INTO r SELECT 'liberar QR1','aplicada:ok',pg_temp.op('liberar','QR1','bbbbbbbb-0000-0000-0000-000000000001','collar perdido','activo');
INSERT INTO r SELECT 'asignar QR1 liberado sin habilitar','rechazada:qr_no_disponible',pg_temp.op('asignar','QR1','bbbbbbbb-0000-0000-0000-000000000002',null,null);
INSERT INTO r SELECT 'habilitar QR1','aplicada:ok',pg_temp.op('habilitar','QR1',null,null,'liberado');
INSERT INTO r SELECT 'reasignar QR1->A2','aplicada:ok',pg_temp.op('asignar','QR1','bbbbbbbb-0000-0000-0000-000000000002',null,'disponible');
INSERT INTO r SELECT 'QR inexistente','rechazada:qr_no_encontrado',pg_temp.op('asignar','NOEXISTE','bbbbbbbb-0000-0000-0000-000000000001',null,null);
SELECT n, CASE WHEN got=esp THEN 'OK' ELSE 'FALLA esperado='||esp||' obtuvo='||got END resultado FROM r WHERE esp<>'ERROR';

-- Acceso: finca ajena
DO $$ BEGIN INSERT INTO qr_operaciones(finca_id,codigo,operacion,creada_en) VALUES ('aaaaaaaa-0000-0000-0000-000000000002','Z','registrar',now()); RAISE NOTICE 'FALLA: permitió finca ajena'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK finca ajena bloqueada: %', SQLERRM; END $$;
-- Cliente no puede escribir directo codigos_qr / historial / auditoria
DO $$ BEGIN UPDATE codigos_qr SET estado='disponible'; RAISE NOTICE 'FALLA update directo codigos_qr'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK update directo codigos_qr: %', SQLERRM; END $$;
DO $$ BEGIN INSERT INTO auditoria(accion) VALUES ('falsa'); RAISE NOTICE 'FALLA insert auditoria'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK insert auditoria: %', SQLERRM; END $$;
DO $$ BEGIN DELETE FROM animales; RAISE NOTICE 'FALLA delete animales'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK delete animales: %', SQLERRM; END $$;
DO $$ DECLARE n int; BEGIN SELECT count(*) INTO n FROM animales; RAISE NOTICE 'u1 ve % animales (esperado 3: finca 1 sin la ajena)', n; SELECT count(*) INTO n FROM fincas; RAISE NOTICE 'u1 ve % fincas (esperado 1)', n; END $$;
-- Pesajes
INSERT INTO pesajes(finca_id,animal_id,fecha_pesaje,valor,naturaleza,metodo) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001',now()-interval '10 days',300,'medido','bascula');
INSERT INTO pesajes(finca_id,animal_id,fecha_pesaje,valor,naturaleza) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001',now()-interval '1 day',310,'estimado');
INSERT INTO pesajes(finca_id,animal_id,fecha_pesaje,valor,naturaleza) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001',now()-interval '20 days',280,'medido');
SELECT 'T pesaje: peso_ultimo=310 estimado' t, peso_ultimo=310 AND peso_ultimo_naturaleza='estimado' ok FROM animales WHERE numero_interno='A-001';
DO $$ BEGIN INSERT INTO pesajes(finca_id,animal_id,fecha_pesaje,valor,naturaleza) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001',now(),0,'medido'); RAISE NOTICE 'FALLA peso 0'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK peso 0 rechazado'; END $$;
DO $$ BEGIN INSERT INTO pesajes(finca_id,animal_id,fecha_pesaje,valor,naturaleza) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001',now(),300,'inventado'); RAISE NOTICE 'FALLA naturaleza'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK naturaleza invalida rechazada'; END $$;
DO $$ BEGIN INSERT INTO pesajes(finca_id,animal_id,fecha_pesaje,valor) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001',now(),300); RAISE NOTICE 'FALLA sin naturaleza'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK sin naturaleza rechazado'; END $$;
DO $$ BEGIN INSERT INTO pesajes(finca_id,animal_id,fecha_pesaje,valor,naturaleza) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000009',now(),300,'medido'); RAISE NOTICE 'FALLA animal ajeno'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK animal de otra finca rechazado'; END $$;
DO $$ BEGIN INSERT INTO pesajes(finca_id,animal_id,fecha_pesaje,valor,naturaleza) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','bbbbbbbb-0000-0000-0000-000000000001',now()+interval '2 days',300,'medido'); RAISE NOTICE 'FALLA futuro'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK fecha futura rechazada'; END $$;
-- anular el pesaje más reciente -> peso_ultimo vuelve al anterior
UPDATE pesajes SET is_deleted=true WHERE valor=310;
SELECT 'T anular pesaje: peso_ultimo=300 medido' t, peso_ultimo=300 AND peso_ultimo_naturaleza='medido' ok FROM animales WHERE numero_interno='A-001';
-- revisión humana
SELECT qr_revisar_operacion(id,'revisado en campo') FROM qr_operaciones WHERE estado='conflicto' AND revisado_en IS NULL LIMIT 1;
SELECT 'T revisión de conflicto' t, count(*)=1 ok FROM qr_operaciones WHERE estado='conflicto' AND revisado_en IS NOT NULL AND nota_revision='revisado en campo';
DO $$ BEGIN PERFORM qr_revisar_operacion(id,'otra') FROM qr_operaciones WHERE estado='aplicada' LIMIT 1; RAISE NOTICE 'FALLA revisar aplicada'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK revisar aplicada rechazado'; END $$;

-- Como superusuario: inmutabilidad
RESET ROLE;
DO $$ BEGIN UPDATE auditoria SET accion='x'; RAISE NOTICE 'FALLA update auditoria'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK update auditoria bloqueado'; END $$;
DO $$ BEGIN DELETE FROM auditoria; RAISE NOTICE 'FALLA delete auditoria'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK delete auditoria bloqueado'; END $$;
DO $$ BEGIN TRUNCATE auditoria; RAISE NOTICE 'FALLA truncate auditoria'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK truncate auditoria bloqueado'; END $$;
DO $$ BEGIN DELETE FROM historial_qr; RAISE NOTICE 'FALLA delete historial'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK delete historial bloqueado'; END $$;
DO $$ BEGIN UPDATE historial_qr SET animal_id=animal_id, fecha_asignacion=now()-interval '1 year'; RAISE NOTICE 'FALLA reescribir historial'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK reescribir historial bloqueado'; END $$;
DO $$ BEGIN UPDATE codigos_qr SET estado='activo' WHERE codigo='QR2'; RAISE NOTICE 'FALLA salto disponible->activo'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK salto de estado bloqueado: %', SQLERRM; END $$;
DO $$ BEGIN UPDATE codigos_qr SET animal_actual_id='bbbbbbbb-0000-0000-0000-000000000001' WHERE codigo='QR1'; RAISE NOTICE 'FALLA reasignar sin liberar'; EXCEPTION WHEN others THEN RAISE NOTICE 'OK reasignar sin liberar bloqueado'; END $$;
DO $$ BEGIN INSERT INTO animales(finca_id,numero_interno) VALUES ('aaaaaaaa-0000-0000-0000-000000000001','A-001'); RAISE NOTICE 'FALLA numero_interno duplicado'; EXCEPTION WHEN unique_violation THEN RAISE NOTICE 'OK numero_interno duplicado rechazado'; END $$;
-- historial: 2 filas, una cerrada con motivo, una abierta
SELECT 'T historial' t, count(*)=2 AND count(*) FILTER (WHERE fecha_liberacion IS NOT NULL AND motivo_liberacion='collar perdido' AND liberado_por IS NOT NULL AND asignado_por IS NOT NULL)=1 ok FROM historial_qr;
SELECT 'T auditoría con actor y finca' t, count(*)>0 AND count(*) FILTER (WHERE actor_id IS NULL)=0 AND count(*) FILTER (WHERE finca_id IS NULL)=0 ok FROM auditoria WHERE tabla_afectada IN ('codigos_qr','historial_qr','pesajes');
SELECT 'T version sube y updated_by sellado' t, version>1 AND updated_by='11111111-1111-1111-1111-111111111111' ok FROM codigos_qr WHERE codigo='QR1';
SELECT tabla_afectada, accion, count(*) FROM auditoria GROUP BY 1,2 ORDER BY 1,2;
