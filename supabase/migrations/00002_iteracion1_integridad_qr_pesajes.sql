-- ============================================================================
-- 00002_iteracion1_integridad_qr_pesajes.sql
-- Sistema Agroecológico Integral para Finca — Iteración 1
-- Fecha: 2026-09-30
--
-- ADITIVA (D-023): NO modifica ni elimina nada de 00001. Solo agrega columnas,
-- tablas, índices, restricciones, triggers y políticas. Es IDEMPOTENTE: se puede
-- ejecutar más de una vez sin duplicar triggers ni romper datos.
--
-- Contenido
--   0. Comprobaciones previas (aborta con mensaje claro si falta algo de 00001)
--   1. Columnas de auditoría estándar aseguradas (DA-030)
--   2. Pertenencia a finca (finca_miembros) + helper es_miembro_finca()
--   3. Columnas nuevas en tablas existentes
--   4. Tablas nuevas: pesajes (DA-025) y qr_operaciones (bandeja de operaciones QR)
--   5. Funciones de trigger
--   6. Triggers
--   7. Restricciones e índices
--   8. Seguridad: privilegios y RLS
--
-- Decisiones tomadas en modo automático (ver Documento Maestro V4, sección 5):
--   DT-002  migración aditiva en lugar de editar 00001
--   DT-003  la máquina de estados del QR vive en la BASE DE DATOS (triggers),
--           no solo en el cliente: nadie puede saltársela escribiendo directo
--   DT-004  conflictos de sincronización: estado 'conflicto' + revisión humana
--   DT-008  pertenencia a finca sin roles (los roles reales siguen pendientes, 34.3)
--   DT-009  interpretación de 'asignado' vs 'activo' del QR (ver sección 5)
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 0. COMPROBACIONES PREVIAS
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['fincas','unidades_espaciales','animales','codigos_qr','historial_qr','auditoria']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      RAISE EXCEPTION '00002 requiere public.% (creada por 00001). PREAPROBACIÓN REQUERIDA: verificar el esquema real.', t;
    END IF;
  END LOOP;
  IF to_regprocedure('public.actualizar_timestamps()') IS NULL THEN
    RAISE EXCEPTION '00002 requiere la función public.actualizar_timestamps() de 00001.';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 1. COLUMNAS DE AUDITORÍA ESTÁNDAR ASEGURADAS (DA-030)
--    En 00001 varias tablas solo declaraban "columnas de auditoría estándar" como
--    comentario. Si ya existen, no se hace nada.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['fincas','unidades_espaciales','animales','codigos_qr','historial_qr']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now()', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now()', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS created_by uuid REFERENCES auth.users(id)', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS updated_by uuid REFERENCES auth.users(id)', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS is_deleted boolean NOT NULL DEFAULT false', t);
  END LOOP;
END $$;

-- ----------------------------------------------------------------------------
-- 2. PERTENENCIA A FINCA (sin roles: 34.3 sigue "esperando información")
--    Persona -> Cuenta -> Rol -> Permiso es la arquitectura final. Mientras no
--    existan personas/roles reales, el único control es "¿esta cuenta pertenece
--    a la finca?". Los permisos granulares se agregan después sobre esta base.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.finca_miembros (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id    uuid NOT NULL REFERENCES public.fincas(id),
  user_id     uuid NOT NULL REFERENCES auth.users(id),
  activo      boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid REFERENCES auth.users(id),
  updated_by  uuid REFERENCES auth.users(id),
  version     integer NOT NULL DEFAULT 1,
  is_deleted  boolean NOT NULL DEFAULT false
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_finca_miembros_finca_user
  ON public.finca_miembros (finca_id, user_id) WHERE NOT is_deleted;

CREATE OR REPLACE FUNCTION public.es_miembro_finca(p_finca uuid)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.finca_miembros m
    WHERE m.finca_id = p_finca
      AND m.user_id  = auth.uid()
      AND m.activo
      AND NOT m.is_deleted
  );
$$;

REVOKE ALL ON FUNCTION public.es_miembro_finca(uuid) FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- 3. COLUMNAS NUEVAS EN TABLAS EXISTENTES
-- ----------------------------------------------------------------------------
-- auditoria: a qué finca pertenece el cambio y por qué se hizo (cadena DA-030)
ALTER TABLE public.auditoria ADD COLUMN IF NOT EXISTS finca_id uuid REFERENCES public.fincas(id);
ALTER TABLE public.auditoria ADD COLUMN IF NOT EXISTS motivo   text;

-- animales: el peso deja de ser un número suelto. peso_ultimo pasa a ser un valor
-- DERIVADO del último pesaje y conserva su naturaleza y fecha (DA-025).
ALTER TABLE public.animales ADD COLUMN IF NOT EXISTS peso_ultimo_naturaleza varchar(20);
ALTER TABLE public.animales ADD COLUMN IF NOT EXISTS peso_ultimo_fecha      timestamptz;

-- codigos_qr: a qué finca pertenece físicamente cada código
ALTER TABLE public.codigos_qr ADD COLUMN IF NOT EXISTS finca_id uuid REFERENCES public.fincas(id);

-- historial_qr: quién, por qué y cuándo (evento vs registro) — nunca se borra (DA-007)
ALTER TABLE public.historial_qr ADD COLUMN IF NOT EXISTS finca_id           uuid REFERENCES public.fincas(id);
ALTER TABLE public.historial_qr ADD COLUMN IF NOT EXISTS motivo_asignacion  text;
ALTER TABLE public.historial_qr ADD COLUMN IF NOT EXISTS motivo_liberacion  text;
ALTER TABLE public.historial_qr ADD COLUMN IF NOT EXISTS asignado_por       uuid REFERENCES auth.users(id);
ALTER TABLE public.historial_qr ADD COLUMN IF NOT EXISTS liberado_por       uuid REFERENCES auth.users(id);
ALTER TABLE public.historial_qr ADD COLUMN IF NOT EXISTS confirmada_en      timestamptz;

-- Relleno de finca_id a partir del animal (solo donde falta). Los QR que nunca
-- tuvieron animal quedan con finca_id NULL: NO se adivina su finca (D-003) y
-- quedan invisibles para los clientes hasta que un administrador los asigne.
UPDATE public.historial_qr h
   SET finca_id = a.finca_id
  FROM public.animales a
 WHERE a.id = h.animal_id AND h.finca_id IS NULL;

UPDATE public.codigos_qr c
   SET finca_id = a.finca_id
  FROM public.animales a
 WHERE a.id = c.animal_actual_id AND c.finca_id IS NULL;

-- ----------------------------------------------------------------------------
-- 4. TABLAS NUEVAS
-- ----------------------------------------------------------------------------
-- 4.1 Dominio de naturaleza del dato (D-004 / DA-025), reutilizable
DO $$
BEGIN
  CREATE DOMAIN public.naturaleza_dato AS varchar(20)
    CHECK (VALUE IN ('observado','medido','estimado','calculado','externo','pronosticado','validado'));
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;

-- 4.2 Pesajes: el peso es un evento con naturaleza, método y responsable.
--     Sin DEFAULT en naturaleza: quien registra DEBE declararla (DA-025).
CREATE TABLE IF NOT EXISTS public.pesajes (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id        uuid NOT NULL REFERENCES public.fincas(id),
  animal_id       uuid NOT NULL REFERENCES public.animales(id),
  fecha_pesaje    timestamptz NOT NULL,                       -- cuándo ocurrió (evento)
  valor           numeric(8,2) NOT NULL CHECK (valor > 0),    -- no existe peso 0 ni negativo
  unidad          varchar(10) NOT NULL DEFAULT 'kg' CHECK (unidad IN ('kg')),
  naturaleza      public.naturaleza_dato NOT NULL,
  metodo          varchar(80),
  responsable_id  uuid REFERENCES auth.users(id),
  evidencia_ref   text,                                       -- referencia a Drive (D-008)
  validado_por    uuid REFERENCES auth.users(id),
  validado_en     timestamptz,
  observaciones   text,
  created_at      timestamptz NOT NULL DEFAULT now(),         -- cuándo se registró
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid REFERENCES auth.users(id),
  updated_by      uuid REFERENCES auth.users(id),
  version         integer NOT NULL DEFAULT 1,
  is_deleted      boolean NOT NULL DEFAULT false
);

-- 4.3 Bandeja de operaciones QR.
--     El cliente (offline-first) solo INSERTA una fila aquí; el servidor aplica la
--     operación, decide el resultado y lo deja escrito en la misma fila, que luego
--     se sincroniza de vuelta. El id lo genera el cliente: reintentar la misma
--     operación nunca duplica (violación de clave primaria = ya procesada).
--       aplicada   -> se ejecutó
--       rechazada  -> viola una regla con el estado actual del servidor
--       conflicto  -> el cliente operó con una vista desactualizada (D-026):
--                     NO se aplica y espera revisión humana
CREATE TABLE IF NOT EXISTS public.qr_operaciones (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id           uuid NOT NULL REFERENCES public.fincas(id),
  codigo             text NOT NULL CHECK (btrim(codigo) <> ''),
  operacion          text NOT NULL CHECK (operacion IN ('registrar','asignar','confirmar','liberar','habilitar')),
  animal_id          uuid REFERENCES public.animales(id),
  motivo             text,
  estado_esperado    text CHECK (estado_esperado IS NULL
                                 OR estado_esperado IN ('disponible','asignado','activo','liberado')),
  creada_en          timestamptz NOT NULL,                    -- hora del evento en el dispositivo
  estado             text NOT NULL DEFAULT 'pendiente'
                       CHECK (estado IN ('pendiente','aplicada','rechazada','conflicto')),
  resultado_detalle  jsonb,
  aplicada_en        timestamptz,
  revisado_por       uuid REFERENCES auth.users(id),
  revisado_en        timestamptz,
  nota_revision      text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  created_by         uuid REFERENCES auth.users(id),
  updated_by         uuid REFERENCES auth.users(id),
  version            integer NOT NULL DEFAULT 1,
  is_deleted         boolean NOT NULL DEFAULT false
);

-- ----------------------------------------------------------------------------
-- 5. FUNCIONES DE TRIGGER
-- ----------------------------------------------------------------------------

-- 5.1 Sella la autoría con la cuenta real y hace inmutables created_* y finca_id.
CREATE OR REPLACE FUNCTION public.sellar_autoria()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.created_by := COALESCE(v_uid, NEW.created_by);
    NEW.updated_by := COALESCE(v_uid, NEW.updated_by, NEW.created_by);
    RETURN NEW;
  END IF;

  NEW.created_at := OLD.created_at;
  NEW.created_by := OLD.created_by;
  NEW.updated_by := COALESCE(v_uid, NEW.updated_by);

  IF (to_jsonb(NEW) -> 'finca_id') IS DISTINCT FROM (to_jsonb(OLD) -> 'finca_id')
     AND (to_jsonb(OLD) ->> 'finca_id') IS NOT NULL THEN
    RAISE EXCEPTION 'finca_id es inmutable (% .%)', TG_TABLE_NAME, OLD.id
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;
  RETURN NEW;
END $$;

-- 5.2 Bloquea la eliminación física: anular != borrar (D-010).
CREATE OR REPLACE FUNCTION public.bloquear_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'No se elimina físicamente % (anular con is_deleted = true)', TG_TABLE_NAME
    USING ERRCODE = 'restrict_violation';
END $$;

CREATE OR REPLACE FUNCTION public.bloquear_truncate()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'TRUNCATE no permitido sobre % (historial inmutable)', TG_TABLE_NAME
    USING ERRCODE = 'restrict_violation';
END $$;

-- 5.3 Auditoría append-only (DA-030). Se ejecuta con los privilegios del dueño:
--     los clientes NO tienen INSERT sobre auditoria, solo este trigger escribe.
--     No registra UPDATEs que solo cambian version/updated_*.
CREATE OR REPLACE FUNCTION public.auditar_cambio()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_old    jsonb;
  v_new    jsonb := to_jsonb(NEW);
  v_accion text;
  v_finca  uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_accion := 'crear';
  ELSE
    v_old := to_jsonb(OLD);
    IF (v_old - 'updated_at' - 'updated_by' - 'version')
       = (v_new - 'updated_at' - 'updated_by' - 'version') THEN
      RETURN NULL;
    END IF;
    v_accion := CASE
      WHEN (v_old ->> 'is_deleted')::boolean = false AND (v_new ->> 'is_deleted')::boolean = true  THEN 'anular'
      WHEN (v_old ->> 'is_deleted')::boolean = true  AND (v_new ->> 'is_deleted')::boolean = false THEN 'restaurar'
      ELSE 'modificar'
    END;
  END IF;

  v_finca := COALESCE((v_new ->> 'finca_id')::uuid,
                      CASE WHEN TG_TABLE_NAME = 'fincas' THEN NEW.id END);

  INSERT INTO public.auditoria
    (actor_id, accion, tabla_afectada, registro_id, estado_anterior, estado_nuevo, finca_id, motivo)
  VALUES
    (auth.uid(), v_accion, TG_TABLE_NAME, NEW.id, v_old, v_new, v_finca,
     NULLIF(current_setting('app.motivo', true), ''));
  RETURN NULL;
END $$;

-- 5.4 auditoria es de solo inserción
CREATE OR REPLACE FUNCTION public.auditoria_inmutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  RAISE EXCEPTION 'auditoria es append-only: no admite % (DA-030)', TG_OP
    USING ERRCODE = 'restrict_violation';
END $$;

-- 5.5 historial_qr: lo ocurrido no se reescribe (DA-007).
--     Solo se puede CERRAR una asignación (liberación) y CONFIRMARLA, una vez.
CREATE OR REPLACE FUNCTION public.historial_qr_protegido()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.codigo_qr_id       IS DISTINCT FROM OLD.codigo_qr_id
  OR NEW.animal_id          IS DISTINCT FROM OLD.animal_id
  OR NEW.fecha_asignacion   IS DISTINCT FROM OLD.fecha_asignacion
  OR NEW.motivo_asignacion  IS DISTINCT FROM OLD.motivo_asignacion
  OR NEW.asignado_por       IS DISTINCT FROM OLD.asignado_por
  OR NEW.is_deleted         IS DISTINCT FROM OLD.is_deleted
  OR (OLD.finca_id IS NOT NULL AND NEW.finca_id IS DISTINCT FROM OLD.finca_id) THEN
    RAISE EXCEPTION 'historial_qr es inmutable: solo se puede cerrar la asignación (DA-007)'
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF OLD.fecha_liberacion IS NOT NULL
     AND (NEW.fecha_liberacion IS DISTINCT FROM OLD.fecha_liberacion
       OR NEW.motivo_liberacion IS DISTINCT FROM OLD.motivo_liberacion
       OR NEW.liberado_por      IS DISTINCT FROM OLD.liberado_por) THEN
    RAISE EXCEPTION 'la asignación ya fue cerrada; no se reescribe'
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF OLD.confirmada_en IS NOT NULL AND NEW.confirmada_en IS DISTINCT FROM OLD.confirmada_en THEN
    RAISE EXCEPTION 'la confirmación ya fue registrada; no se reescribe'
      USING ERRCODE = 'restrict_violation';
  END IF;

  IF NEW.fecha_liberacion IS NOT NULL AND NEW.fecha_liberacion < NEW.fecha_asignacion THEN
    RAISE EXCEPTION 'fecha_liberacion no puede ser anterior a fecha_asignacion'
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

-- 5.6 Máquina de estados del QR, aplicada SIEMPRE, escriba quien escriba (DT-003).
--   disponible -> asignado -> activo -> liberado -> disponible
--   asignado -> liberado (se cancela la asignación antes de confirmarla)
--   DT-009: 'asignado' = vinculado a un animal en el sistema, aún sin confirmar
--           que la chapa física está puesta; 'activo' = vinculación confirmada.
--   'liberado' -> 'disponible' exige un paso explícito (chapa recuperada).
CREATE OR REPLACE FUNCTION public.qr_transicion_valida()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.estado <> 'disponible' OR NEW.animal_actual_id IS NOT NULL THEN
      RAISE EXCEPTION 'un QR nuevo debe nacer disponible y sin animal'
        USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.codigo IS DISTINCT FROM OLD.codigo THEN
    RAISE EXCEPTION 'el código de un QR es inmutable' USING ERRCODE = 'restrict_violation';
  END IF;

  IF NEW.estado IS DISTINCT FROM OLD.estado THEN
    IF NOT (   (OLD.estado = 'disponible' AND NEW.estado = 'asignado')
            OR (OLD.estado = 'asignado'   AND NEW.estado IN ('activo','liberado'))
            OR (OLD.estado = 'activo'     AND NEW.estado = 'liberado')
            OR (OLD.estado = 'liberado'   AND NEW.estado = 'disponible')) THEN
      RAISE EXCEPTION 'transición de QR no permitida: % -> %', OLD.estado, NEW.estado
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;

  IF OLD.estado IN ('asignado','activo') AND NEW.estado IN ('asignado','activo')
     AND NEW.animal_actual_id IS DISTINCT FROM OLD.animal_actual_id THEN
    RAISE EXCEPTION 'libere el QR antes de reasignarlo a otro animal (DA-007)'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END $$;

-- 5.7 Coherencia de pesajes: el animal pertenece a la finca; fechas razonables.
CREATE OR REPLACE FUNCTION public.pesajes_coherencia()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_finca uuid;
BEGIN
  SELECT finca_id INTO v_finca FROM public.animales WHERE id = NEW.animal_id;
  IF v_finca IS NULL OR v_finca <> NEW.finca_id THEN
    RAISE EXCEPTION 'el animal % no pertenece a la finca %', NEW.animal_id, NEW.finca_id
      USING ERRCODE = 'integrity_constraint_violation';
  END IF;

  IF TG_OP = 'UPDATE' AND NEW.animal_id IS DISTINCT FROM OLD.animal_id THEN
    RAISE EXCEPTION 'un pesaje no puede cambiarse de animal (corrija anulando y registrando de nuevo)'
      USING ERRCODE = 'restrict_violation';
  END IF;

  -- tolerancia técnica por desfase de reloj del dispositivo
  IF NEW.fecha_pesaje > now() + interval '10 minutes' THEN
    RAISE EXCEPTION 'fecha_pesaje en el futuro' USING ERRCODE = 'check_violation';
  END IF;

  IF (NEW.validado_por IS NULL) <> (NEW.validado_en IS NULL) THEN
    RAISE EXCEPTION 'validado_por y validado_en van juntos' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END $$;

-- 5.8 animales.peso_ultimo es DERIVADO del último pesaje vigente. Sin pesajes
--     queda NULL (N/A), nunca 0 (D-003).
CREATE OR REPLACE FUNCTION public.sincronizar_peso_ultimo()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_valor numeric(8,2);
  v_nat   varchar(20);
  v_fecha timestamptz;
BEGIN
  SELECT p.valor, p.naturaleza, p.fecha_pesaje
    INTO v_valor, v_nat, v_fecha
    FROM public.pesajes p
   WHERE p.animal_id = NEW.animal_id AND NOT p.is_deleted
   ORDER BY p.fecha_pesaje DESC, p.created_at DESC
   LIMIT 1;

  UPDATE public.animales a
     SET peso_ultimo = v_valor,
         peso_ultimo_naturaleza = v_nat,
         peso_ultimo_fecha = v_fecha
   WHERE a.id = NEW.animal_id
     AND (a.peso_ultimo IS DISTINCT FROM v_valor
       OR a.peso_ultimo_naturaleza IS DISTINCT FROM v_nat
       OR a.peso_ultimo_fecha IS DISTINCT FROM v_fecha);
  RETURN NULL;
END $$;

-- 5.9 Aplicación de operaciones QR (bandeja). Corre como dueño para poder escribir
--     codigos_qr/historial_qr, pero SOLO tras verificar pertenencia a la finca.
--     PERMISOS GRANULARES PENDIENTES (34.3): hoy basta con pertenecer a la finca.
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

-- 5.10 Una operación ya procesada solo admite la marca de revisión humana.
CREATE OR REPLACE FUNCTION public.qr_operaciones_inmutable()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_excluir text[] := ARRAY['revisado_por','revisado_en','nota_revision','updated_at','updated_by','version'];
BEGIN
  IF (to_jsonb(NEW) - v_excluir) IS DISTINCT FROM (to_jsonb(OLD) - v_excluir) THEN
    RAISE EXCEPTION 'una operación QR procesada es inmutable; solo admite revisión'
      USING ERRCODE = 'restrict_violation';
  END IF;
  RETURN NEW;
END $$;

-- 5.11 Revisión humana de operaciones rechazadas o en conflicto (D-026).
--      Marcar como revisada NO reaplica nada: quien revisa emite, si quiere,
--      una operación nueva con una vista actualizada.
CREATE OR REPLACE FUNCTION public.qr_revisar_operacion(p_id uuid, p_nota text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_op public.qr_operaciones%ROWTYPE;
BEGIN
  SELECT * INTO v_op FROM public.qr_operaciones WHERE id = p_id AND NOT is_deleted;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'operación no encontrada' USING ERRCODE = 'no_data_found';
  END IF;
  IF auth.uid() IS NULL OR NOT public.es_miembro_finca(v_op.finca_id) THEN
    RAISE EXCEPTION 'Sin acceso a la finca indicada' USING ERRCODE = 'insufficient_privilege';
  END IF;
  IF v_op.estado NOT IN ('rechazada','conflicto') THEN
    RAISE EXCEPTION 'solo se revisan operaciones rechazadas o en conflicto' USING ERRCODE = 'check_violation';
  END IF;
  IF btrim(coalesce(p_nota, '')) = '' THEN
    RAISE EXCEPTION 'la revisión exige una nota' USING ERRCODE = 'check_violation';
  END IF;
  IF v_op.revisado_en IS NOT NULL THEN
    RAISE EXCEPTION 'la operación ya fue revisada' USING ERRCODE = 'check_violation';
  END IF;
  UPDATE public.qr_operaciones
     SET revisado_por = auth.uid(), revisado_en = now(), nota_revision = p_nota
   WHERE id = p_id;
END $$;

REVOKE ALL ON FUNCTION public.qr_revisar_operacion(uuid, text) FROM PUBLIC;

-- ----------------------------------------------------------------------------
-- 6. TRIGGERS
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  t text;
  v_tablas text[] := ARRAY['fincas','unidades_espaciales','animales','codigos_qr','historial_qr',
                           'finca_miembros','pesajes','qr_operaciones'];
BEGIN
  FOREACH t IN ARRAY v_tablas
  LOOP
    -- autoría real + inmutabilidad de created_* y finca_id
    EXECUTE format('DROP TRIGGER IF EXISTS t10_sellar_autoria ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t10_sellar_autoria BEFORE INSERT OR UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.sellar_autoria()', t);

    -- timestamps/version: solo si la tabla no tiene ya el trigger de 00001
    IF NOT EXISTS (
      SELECT 1 FROM pg_trigger g
       WHERE g.tgrelid = format('public.%I', t)::regclass
         AND NOT g.tgisinternal
         AND g.tgfoid = 'public.actualizar_timestamps()'::regprocedure
    ) THEN
      EXECUTE format('CREATE TRIGGER t20_timestamps BEFORE UPDATE ON public.%I
                      FOR EACH ROW EXECUTE FUNCTION public.actualizar_timestamps()', t);
    END IF;

    -- sin eliminación física
    EXECUTE format('DROP TRIGGER IF EXISTS t30_bloquear_delete ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t30_bloquear_delete BEFORE DELETE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.bloquear_delete()', t);

    -- auditoría transversal (DA-030)
    EXECUTE format('DROP TRIGGER IF EXISTS t90_auditar ON public.%I', t);
    EXECUTE format('CREATE TRIGGER t90_auditar AFTER INSERT OR UPDATE ON public.%I
                    FOR EACH ROW EXECUTE FUNCTION public.auditar_cambio()', t);
  END LOOP;
END $$;

-- auditoria: solo inserción
DROP TRIGGER IF EXISTS t10_auditoria_inmutable ON public.auditoria;
CREATE TRIGGER t10_auditoria_inmutable BEFORE UPDATE OR DELETE ON public.auditoria
  FOR EACH ROW EXECUTE FUNCTION public.auditoria_inmutable();
DROP TRIGGER IF EXISTS t10_auditoria_sin_truncate ON public.auditoria;
CREATE TRIGGER t10_auditoria_sin_truncate BEFORE TRUNCATE ON public.auditoria
  FOR EACH STATEMENT EXECUTE FUNCTION public.bloquear_truncate();

-- historial_qr: nunca se borra ni se vacía
DROP TRIGGER IF EXISTS t10_historial_sin_truncate ON public.historial_qr;
CREATE TRIGGER t10_historial_sin_truncate BEFORE TRUNCATE ON public.historial_qr
  FOR EACH STATEMENT EXECUTE FUNCTION public.bloquear_truncate();
DROP TRIGGER IF EXISTS t50_historial_protegido ON public.historial_qr;
CREATE TRIGGER t50_historial_protegido BEFORE UPDATE ON public.historial_qr
  FOR EACH ROW EXECUTE FUNCTION public.historial_qr_protegido();

-- codigos_qr: máquina de estados
DROP TRIGGER IF EXISTS t50_qr_transicion ON public.codigos_qr;
CREATE TRIGGER t50_qr_transicion BEFORE INSERT OR UPDATE ON public.codigos_qr
  FOR EACH ROW EXECUTE FUNCTION public.qr_transicion_valida();

-- qr_operaciones: aplica la operación al insertar; luego es inmutable
DROP TRIGGER IF EXISTS t50_qr_aplicar ON public.qr_operaciones;
CREATE TRIGGER t50_qr_aplicar BEFORE INSERT ON public.qr_operaciones
  FOR EACH ROW EXECUTE FUNCTION public.qr_operaciones_aplicar();
DROP TRIGGER IF EXISTS t50_qr_op_inmutable ON public.qr_operaciones;
CREATE TRIGGER t50_qr_op_inmutable BEFORE UPDATE ON public.qr_operaciones
  FOR EACH ROW EXECUTE FUNCTION public.qr_operaciones_inmutable();

-- pesajes
DROP TRIGGER IF EXISTS t50_pesajes_coherencia ON public.pesajes;
CREATE TRIGGER t50_pesajes_coherencia BEFORE INSERT OR UPDATE ON public.pesajes
  FOR EACH ROW EXECUTE FUNCTION public.pesajes_coherencia();
DROP TRIGGER IF EXISTS t60_peso_ultimo ON public.pesajes;
CREATE TRIGGER t60_peso_ultimo AFTER INSERT OR UPDATE ON public.pesajes
  FOR EACH ROW EXECUTE FUNCTION public.sincronizar_peso_ultimo();

-- ----------------------------------------------------------------------------
-- 7. RESTRICCIONES E ÍNDICES
-- ----------------------------------------------------------------------------
-- 7.1 numero_interno identifica al animal dentro de la finca (DA-007).
--     Si hubiera duplicados reales, la migración se detiene: hay que decidir
--     con el usuario cuál es cuál (no se adivina).
DO $$
DECLARE
  v_dup integer;
BEGIN
  SELECT count(*) INTO v_dup FROM (
    SELECT finca_id, numero_interno FROM public.animales
     WHERE NOT is_deleted GROUP BY 1, 2 HAVING count(*) > 1
  ) d;
  IF v_dup > 0 THEN
    RAISE EXCEPTION 'Hay % numero_interno duplicados en animales. PREAPROBACIÓN REQUERIDA: resolver antes de continuar.', v_dup;
  END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS ux_animales_finca_numero
  ON public.animales (finca_id, numero_interno) WHERE NOT is_deleted;

-- 7.2 Como máximo una asignación abierta por QR y por animal (DA-007)
CREATE UNIQUE INDEX IF NOT EXISTS ux_historial_qr_abierto_por_qr
  ON public.historial_qr (codigo_qr_id) WHERE fecha_liberacion IS NULL AND NOT is_deleted;
CREATE UNIQUE INDEX IF NOT EXISTS ux_historial_qr_abierto_por_animal
  ON public.historial_qr (animal_id) WHERE fecha_liberacion IS NULL AND NOT is_deleted;

-- 7.3 Estados y coherencia del QR. NOT VALID protege lo nuevo sin reventar si
--     hubiera filas antiguas dudosas; luego se intenta validar y, si no se puede,
--     se avisa (no se corrige nada en silencio).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_codigos_qr_estado') THEN
    ALTER TABLE public.codigos_qr ADD CONSTRAINT ck_codigos_qr_estado
      CHECK (estado IN ('disponible','asignado','activo','liberado')) NOT VALID;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'ck_codigos_qr_animal_coherente') THEN
    ALTER TABLE public.codigos_qr ADD CONSTRAINT ck_codigos_qr_animal_coherente
      CHECK ((estado IN ('asignado','activo')) = (animal_actual_id IS NOT NULL)) NOT VALID;
  END IF;
  BEGIN
    ALTER TABLE public.codigos_qr VALIDATE CONSTRAINT ck_codigos_qr_estado;
    ALTER TABLE public.codigos_qr VALIDATE CONSTRAINT ck_codigos_qr_animal_coherente;
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'Hay filas antiguas de codigos_qr que violan las restricciones: quedan sin validar. Revisar a mano.';
  END;
END $$;

-- 7.4 Índices de rendimiento (Documento Maestro V4, 9.1)
CREATE INDEX IF NOT EXISTS ix_animales_finca_cat_estado
  ON public.animales (finca_id, categoria, estado) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS ix_animales_finca_updated
  ON public.animales (finca_id, updated_at);
CREATE INDEX IF NOT EXISTS ix_unidades_finca_tipo
  ON public.unidades_espaciales (finca_id, tipo) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS ix_unidades_geometria
  ON public.unidades_espaciales USING gist (geometria);
CREATE INDEX IF NOT EXISTS ix_codigos_qr_finca_estado
  ON public.codigos_qr (finca_id, estado) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS ix_historial_qr_animal
  ON public.historial_qr (animal_id, fecha_asignacion DESC);
CREATE INDEX IF NOT EXISTS ix_historial_qr_codigo
  ON public.historial_qr (codigo_qr_id, fecha_asignacion DESC);
CREATE INDEX IF NOT EXISTS ix_pesajes_animal_fecha
  ON public.pesajes (animal_id, fecha_pesaje DESC, created_at DESC) WHERE NOT is_deleted;
CREATE INDEX IF NOT EXISTS ix_qr_operaciones_finca_estado
  ON public.qr_operaciones (finca_id, estado, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_auditoria_objeto
  ON public.auditoria (tabla_afectada, registro_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_auditoria_finca
  ON public.auditoria (finca_id, created_at DESC);

-- ----------------------------------------------------------------------------
-- 8. SEGURIDAD: PRIVILEGIOS Y RLS
--    Las tablas de QR y la auditoría NO se escriben directo desde el cliente:
--    el cliente solo inserta en qr_operaciones; los triggers hacen el resto.
--    PowerSync lee por replicación (no pasa por RLS): sus sync rules deben
--    filtrar por finca_miembros. auditoria NO debe subirse desde el cliente.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['fincas','finca_miembros','unidades_espaciales','animales',
                           'codigos_qr','historial_qr','pesajes','qr_operaciones','auditoria']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    EXECUTE 'REVOKE ALL ON public.fincas, public.finca_miembros, public.unidades_espaciales, public.animales,
                           public.codigos_qr, public.historial_qr, public.pesajes, public.qr_operaciones,
                           public.auditoria FROM anon';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    -- solo lectura para el cliente
    EXECUTE 'REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.fincas, public.finca_miembros,
                           public.codigos_qr, public.historial_qr, public.auditoria FROM authenticated';
    -- nadie elimina físicamente
    EXECUTE 'REVOKE DELETE, TRUNCATE ON public.unidades_espaciales, public.animales, public.pesajes,
                           public.qr_operaciones FROM authenticated';
    -- qr_operaciones: el cliente solo inserta; la revisión va por función
    EXECUTE 'REVOKE UPDATE ON public.qr_operaciones FROM authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.qr_revisar_operacion(uuid, text) TO authenticated';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.es_miembro_finca(uuid) TO authenticated';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    EXECUTE 'REVOKE UPDATE, DELETE, TRUNCATE ON public.auditoria FROM service_role';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.es_miembro_finca(uuid) TO service_role';
  END IF;
END $$;

-- Políticas propias (prefijo p02_). Si 00001 ya creó otras, las políticas
-- permisivas se SUMAN (OR): verificar en el esquema real que no ensanchen el acceso.
DO $$
DECLARE
  t text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    RAISE NOTICE 'Rol authenticated inexistente: se omiten las políticas RLS.';
    RETURN;
  END IF;

  -- lectura por pertenencia a la finca
  FOREACH t IN ARRAY ARRAY['unidades_espaciales','animales','codigos_qr','historial_qr',
                           'pesajes','qr_operaciones']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS p02_%s_select ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p02_%s_select ON public.%I FOR SELECT TO authenticated
                    USING (finca_id IS NOT NULL AND public.es_miembro_finca(finca_id))', t, t);
  END LOOP;

  -- escritura por pertenencia (los permisos granulares llegan con 34.3)
  FOREACH t IN ARRAY ARRAY['unidades_espaciales','animales','pesajes']
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS p02_%s_insert ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p02_%s_insert ON public.%I FOR INSERT TO authenticated
                    WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
    EXECUTE format('DROP POLICY IF EXISTS p02_%s_update ON public.%I', t, t);
    EXECUTE format('CREATE POLICY p02_%s_update ON public.%I FOR UPDATE TO authenticated
                    USING (public.es_miembro_finca(finca_id))
                    WITH CHECK (public.es_miembro_finca(finca_id))', t, t);
  END LOOP;

  -- la bandeja QR: el cliente solo inserta
  DROP POLICY IF EXISTS p02_qr_operaciones_insert ON public.qr_operaciones;
  CREATE POLICY p02_qr_operaciones_insert ON public.qr_operaciones FOR INSERT TO authenticated
    WITH CHECK (public.es_miembro_finca(finca_id));

  -- fincas y pertenencias: solo lectura
  DROP POLICY IF EXISTS p02_fincas_select ON public.fincas;
  CREATE POLICY p02_fincas_select ON public.fincas FOR SELECT TO authenticated
    USING (public.es_miembro_finca(id));
  DROP POLICY IF EXISTS p02_finca_miembros_select ON public.finca_miembros;
  CREATE POLICY p02_finca_miembros_select ON public.finca_miembros FOR SELECT TO authenticated
    USING (user_id = auth.uid());

  -- auditoría: lectura por finca
  DROP POLICY IF EXISTS p02_auditoria_select ON public.auditoria;
  CREATE POLICY p02_auditoria_select ON public.auditoria FOR SELECT TO authenticated
    USING (finca_id IS NOT NULL AND public.es_miembro_finca(finca_id));
END $$;

-- ----------------------------------------------------------------------------
-- NOTAS DE OPERACIÓN (no se ejecutan)
--
-- Alta inicial de la finca y del primer usuario (hace el administrador con el
-- rol de servicio; los clientes no pueden):
--   INSERT INTO public.fincas (nombre) VALUES ('<nombre real>') RETURNING id;
--   INSERT INTO public.finca_miembros (finca_id, user_id) VALUES ('<id finca>', '<id usuario auth>');
--
-- Pendiente de la migración opcional "restricciones de dominio" (no incluida a
-- propósito, porque dependen de valores que escribe el cliente Flutter aún no
-- visto): CHECK de animales.categoria (5 categorías, D-013) y de
-- animales.fecha_nacimiento_naturaleza. Tabla animal_lote: espera confirmar que
-- lotes_ganaderos existe realmente (brecha CHG-008).
-- ----------------------------------------------------------------------------
