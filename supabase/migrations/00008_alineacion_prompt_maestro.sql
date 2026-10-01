-- ============================================================================
-- 00008_alineacion_prompt_maestro.sql — ADITIVA e idempotente. Requiere 00002–00007.
-- Alinea la base con el Prompt Maestro de Continuidad (CHG-010/011):
--  1. QR: no se reasigna mientras existan operaciones pendientes de revisión.
--  2. Evidencias: tipo de foto 'identificacion'.
--  3. Calidad de datos (estados + nota) en pesajes, aforos y evidencias.
--  4. Fecha de sincronización (servidor) separada de fecha del hecho y de registro.
-- No inventa datos: solo estructura y reglas.
-- ============================================================================
DO $$ BEGIN
  IF to_regclass('public.aforos') IS NULL OR to_regclass('public.evidencias_animal') IS NULL THEN
    RAISE EXCEPTION '00008 requiere 00002 a 00007.';
  END IF;
END $$;

-- 1. QR (se redefine la función de 00002 añadiendo la regla) ------------------
CREATE OR REPLACE FUNCTION public.qr_operaciones_aplicar()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_ahora   timestamptz := now();
  v_codigo  text := btrim(NEW.codigo);
  v_qr      public.codigos_qr%ROWTYPE;
  v_animal  public.animales%ROWTYPE;
  v_abierto public.historial_qr%ROWTYPE;
  v_otro    text;
  v_res     text := 'aplicada';
  v_err     text;
  v_msg     text;
BEGIN
  IF v_uid IS NULL OR NOT public.es_miembro_finca(NEW.finca_id) THEN
    RAISE EXCEPTION 'Sin acceso a la finca indicada' USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Campos que solo decide el servidor: el cliente no puede falsificarlos.
  NEW.codigo := v_codigo;
  NEW.estado := 'pendiente';
  NEW.resultado_detalle := NULL;
  NEW.aplicada_en := NULL;
  NEW.revisado_por := NULL;
  NEW.revisado_en := NULL;
  NEW.nota_revision := NULL;

  <<proceso>>
  LOOP
    -- tolerancia técnica por desfase de reloj del dispositivo
    IF NEW.creada_en > v_ahora + interval '10 minutes' THEN
      v_res := 'rechazada'; v_err := 'fecha_futura'; EXIT proceso;
    END IF;
    IF NEW.operacion IN ('asignar','confirmar','liberar') AND NEW.animal_id IS NULL THEN
      v_res := 'rechazada'; v_err := 'animal_requerido'; EXIT proceso;
    END IF;
    IF NEW.operacion = 'liberar' AND btrim(coalesce(NEW.motivo, '')) = '' THEN
      v_res := 'rechazada'; v_err := 'motivo_requerido'; EXIT proceso;
    END IF;

    -- registrar: da de alta un código físico nuevo
    IF NEW.operacion = 'registrar' THEN
      IF EXISTS (SELECT 1 FROM public.codigos_qr WHERE codigo = v_codigo) THEN
        v_res := 'rechazada'; v_err := 'codigo_existente'; EXIT proceso;
      END IF;
      INSERT INTO public.codigos_qr (codigo, estado, finca_id)
      VALUES (v_codigo, 'disponible', NEW.finca_id)
      RETURNING * INTO v_qr;
      EXIT proceso;
    END IF;

    SELECT * INTO v_qr
      FROM public.codigos_qr
     WHERE codigo = v_codigo AND finca_id = NEW.finca_id AND NOT is_deleted
       FOR UPDATE;
    IF NOT FOUND THEN
      v_res := 'rechazada'; v_err := 'qr_no_encontrado'; EXIT proceso;
    END IF;

    -- CONFLICTO: el cliente operó con una vista desactualizada -> no se aplica
    IF NEW.estado_esperado IS NOT NULL AND NEW.estado_esperado <> v_qr.estado THEN
      v_res := 'conflicto'; v_err := 'estado_divergente';
      v_msg := format('el cliente esperaba "%s" y el servidor tiene "%s"', NEW.estado_esperado, v_qr.estado);
      EXIT proceso;
    END IF;
    IF NEW.operacion IN ('confirmar','liberar')
       AND NEW.animal_id IS DISTINCT FROM v_qr.animal_actual_id THEN
      v_res := 'conflicto'; v_err := 'animal_divergente';
      v_msg := 'el animal indicado no es el que tiene el QR en el servidor';
      EXIT proceso;
    END IF;

    IF NEW.operacion = 'asignar' THEN
      IF v_qr.estado <> 'disponible' THEN
        v_res := 'rechazada'; v_err := 'qr_no_disponible'; EXIT proceso;
      END IF;
      -- 00008: no se reasigna un QR con operaciones pendientes de revision
      IF EXISTS (SELECT 1 FROM public.qr_operaciones o
                  WHERE o.finca_id = NEW.finca_id AND o.codigo = v_codigo AND NOT o.is_deleted
                    AND o.id IS DISTINCT FROM NEW.id
                    AND (o.estado = 'pendiente' OR (o.estado = 'conflicto' AND o.revisado_en IS NULL))) THEN
        v_res := 'rechazada'; v_err := 'operaciones_pendientes';
        v_msg := 'el QR tiene operaciones pendientes de revision; resuelvalas antes de reasignar';
        EXIT proceso;
      END IF;
      SELECT * INTO v_animal
        FROM public.animales
       WHERE id = NEW.animal_id AND finca_id = NEW.finca_id AND NOT is_deleted
         FOR UPDATE;
      IF NOT FOUND THEN
        v_res := 'rechazada'; v_err := 'animal_no_encontrado'; EXIT proceso;
      END IF;
      IF v_animal.estado IS DISTINCT FROM 'activo' THEN
        v_res := 'rechazada'; v_err := 'animal_no_activo'; EXIT proceso;
      END IF;
      SELECT c.codigo INTO v_otro
        FROM public.historial_qr h
        JOIN public.codigos_qr c ON c.id = h.codigo_qr_id
       WHERE h.animal_id = NEW.animal_id AND h.fecha_liberacion IS NULL AND NOT h.is_deleted
       LIMIT 1;
      IF FOUND THEN
        v_res := 'rechazada'; v_err := 'animal_con_qr';
        v_msg := format('el animal ya tiene asignado %s; libérelo antes', v_otro);
        EXIT proceso;
      END IF;
      BEGIN
        UPDATE public.codigos_qr
           SET estado = 'asignado', animal_actual_id = NEW.animal_id
         WHERE id = v_qr.id
        RETURNING * INTO v_qr;
        INSERT INTO public.historial_qr
          (codigo_qr_id, animal_id, finca_id, fecha_asignacion, motivo_asignacion, asignado_por)
        VALUES
          (v_qr.id, NEW.animal_id, NEW.finca_id, NEW.creada_en, NEW.motivo, v_uid);
      EXCEPTION WHEN unique_violation THEN
        v_res := 'rechazada'; v_err := 'violacion_unicidad';
      END;
      EXIT proceso;
    END IF;

    IF NEW.operacion = 'confirmar' THEN
      IF v_qr.estado = 'activo' THEN
        v_msg := 'ya_aplicada'; EXIT proceso;                 -- idempotente
      END IF;
      IF v_qr.estado <> 'asignado' THEN
        v_res := 'rechazada'; v_err := 'qr_no_asignado'; EXIT proceso;
      END IF;
      UPDATE public.historial_qr
         SET confirmada_en = NEW.creada_en
       WHERE codigo_qr_id = v_qr.id AND fecha_liberacion IS NULL AND NOT is_deleted;
      UPDATE public.codigos_qr SET estado = 'activo' WHERE id = v_qr.id RETURNING * INTO v_qr;
      EXIT proceso;
    END IF;

    IF NEW.operacion = 'liberar' THEN
      IF v_qr.estado NOT IN ('asignado','activo') THEN
        v_res := 'rechazada'; v_err := 'qr_no_asignado'; EXIT proceso;
      END IF;
      SELECT * INTO v_abierto
        FROM public.historial_qr
       WHERE codigo_qr_id = v_qr.id AND fecha_liberacion IS NULL AND NOT is_deleted
         FOR UPDATE;
      IF NOT FOUND THEN
        v_res := 'rechazada'; v_err := 'historial_inconsistente'; EXIT proceso;
      END IF;
      IF NEW.creada_en < v_abierto.fecha_asignacion THEN
        v_res := 'rechazada'; v_err := 'fecha_anterior_a_asignacion'; EXIT proceso;
      END IF;
      UPDATE public.historial_qr
         SET fecha_liberacion = NEW.creada_en,
             motivo_liberacion = NEW.motivo,
             liberado_por = v_uid
       WHERE id = v_abierto.id;
      UPDATE public.codigos_qr
         SET estado = 'liberado', animal_actual_id = NULL
       WHERE id = v_qr.id
      RETURNING * INTO v_qr;
      EXIT proceso;
    END IF;

    IF NEW.operacion = 'habilitar' THEN
      IF v_qr.estado = 'disponible' THEN
        v_msg := 'ya_aplicada'; EXIT proceso;                 -- idempotente
      END IF;
      IF v_qr.estado <> 'liberado' THEN
        v_res := 'rechazada'; v_err := 'qr_no_liberado'; EXIT proceso;
      END IF;
      UPDATE public.codigos_qr SET estado = 'disponible' WHERE id = v_qr.id RETURNING * INTO v_qr;
      EXIT proceso;
    END IF;

    v_res := 'rechazada'; v_err := 'operacion_desconocida';
    EXIT proceso;
  END LOOP proceso;

  NEW.estado := v_res;
  NEW.aplicada_en := CASE WHEN v_res = 'aplicada' THEN v_ahora END;
  NEW.resultado_detalle := jsonb_strip_nulls(jsonb_build_object(
    'codigo_error', v_err,
    'mensaje', v_msg,
    'qr_estado', v_qr.estado,
    'qr_animal_actual_id', v_qr.animal_actual_id,
    'servidor_en', v_ahora));
  RETURN NEW;
END $$;

-- 2. Evidencias: tipo 'identificacion' ----------------------------------------
DO $$
DECLARE c text;
BEGIN
  FOR c IN SELECT conname FROM pg_constraint
            WHERE conrelid = 'public.evidencias_animal'::regclass AND contype = 'c'
              AND pg_get_constraintdef(oid) LIKE '%principal%serie_corporal%' LOOP
    EXECUTE format('ALTER TABLE public.evidencias_animal DROP CONSTRAINT %I', c);
  END LOOP;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'evidencias_animal_tipo_chk') THEN
    ALTER TABLE public.evidencias_animal ADD CONSTRAINT evidencias_animal_tipo_chk
      CHECK (tipo IN ('principal','identificacion','serie_corporal','zona_especifica','ubre'));
  END IF;
END $$;

-- 3. Calidad de datos ------------------------------------------------------------
DO $$ BEGIN
  CREATE DOMAIN public.estado_calidad_dato AS varchar(20)
    CHECK (VALUE IN ('pendiente','registrado','en_revision','validado','inconsistente',
                     'rechazado','corregido','reemplazado','no_disponible','no_aplica'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['pesajes','aforos','evidencias_animal'] LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS estado_calidad public.estado_calidad_dato NOT NULL DEFAULT ''registrado''', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS nota_calidad text', t);
  END LOOP;
END $$;

-- Marcar un estado problemático exige nota; validar un pesaje exige validador.
-- Nunca se borra automáticamente: solo cambia el estado (y queda auditado).
CREATE OR REPLACE FUNCTION public.calidad_dato_reglas()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN
  IF NEW.estado_calidad IN ('inconsistente','rechazado','corregido','reemplazado','en_revision')
     AND btrim(coalesce(NEW.nota_calidad, '')) = '' THEN
    RAISE EXCEPTION 'estado "%" exige nota_calidad (que se observo)', NEW.estado_calidad
      USING ERRCODE = 'check_violation';
  END IF;
  IF TG_TABLE_NAME = 'pesajes' AND NEW.estado_calidad = 'validado' THEN
    IF to_jsonb(NEW)->>'validado_por' IS NULL OR to_jsonb(NEW)->>'validado_en' IS NULL THEN
      RAISE EXCEPTION 'validar un pesaje exige validado_por y validado_en' USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- 4. Fecha de sincronización: la fija el SERVIDOR; el cliente no la falsifica ----
CREATE OR REPLACE FUNCTION public.sellar_sincronizacion()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN NEW.sincronizada_en := now(); RETURN NEW; END $$;

CREATE OR REPLACE FUNCTION public.proteger_sincronizacion()
RETURNS trigger LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN NEW.sincronizada_en := OLD.sincronizada_en; RETURN NEW; END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['pesajes','evidencias_animal','animal_lote','ocupaciones_pastoreo','aforos','qr_operaciones'] LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS sincronizada_en timestamptz', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t12_sincronizacion_ins ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t12_sincronizacion_ins BEFORE INSERT ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.sellar_sincronizacion()', t);
    EXECUTE format('DROP TRIGGER IF EXISTS t12_sincronizacion_upd ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t12_sincronizacion_upd BEFORE UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.proteger_sincronizacion()', t);
  END LOOP;
  FOREACH t IN ARRAY ARRAY['pesajes','aforos','evidencias_animal'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS t55_calidad_dato ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t55_calidad_dato BEFORE INSERT OR UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.calidad_dato_reglas()', t);
  END LOOP;
END $$;
