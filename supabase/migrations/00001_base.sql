-- ============================================================================
-- 00001_base.sql — Base del sistema (tablas núcleo). Idempotente.
-- Origen: reconstrucción del 00001 que el usuario pegó en conversaciones previas
-- (fincas, unidades espaciales, animales, QR, historial QR, auditoría). El proyecto
-- Supabase "finca-hato-claros" se creó vacío el 1-oct-2026, así que esta es la base real.
-- Las migraciones 00002+ le agregan auditoría, reglas, RLS y módulos.
-- ============================================================================
CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS postgis WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.actualizar_timestamps() RETURNS trigger
LANGUAGE plpgsql SET search_path = public, pg_temp AS $$
BEGIN NEW.updated_at := now(); NEW.version := OLD.version + 1; RETURN NEW; END $$;

CREATE TABLE IF NOT EXISTS public.fincas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre text NOT NULL
);
CREATE TABLE IF NOT EXISTS public.unidades_espaciales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  parent_id uuid REFERENCES public.unidades_espaciales(id),
  tipo varchar(40),
  nombre text,
  geometria extensions.geometry(Polygon, 4326),
  es_temporal boolean DEFAULT false,
  estado varchar(20)
);
CREATE TABLE IF NOT EXISTS public.animales (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  finca_id uuid NOT NULL REFERENCES public.fincas(id),
  numero_interno varchar(40) NOT NULL,
  categoria varchar(30),
  sexo varchar(10),
  fecha_nacimiento date,
  fecha_nacimiento_naturaleza varchar(20) DEFAULT 'estimada',
  estado varchar(20) DEFAULT 'activo',
  peso_ultimo numeric(8,2)
);
CREATE TABLE IF NOT EXISTS public.codigos_qr (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo text UNIQUE NOT NULL,
  estado varchar(20) DEFAULT 'disponible',
  animal_actual_id uuid UNIQUE REFERENCES public.animales(id)
);
CREATE TABLE IF NOT EXISTS public.historial_qr (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  codigo_qr_id uuid NOT NULL REFERENCES public.codigos_qr(id),
  animal_id uuid NOT NULL REFERENCES public.animales(id),
  fecha_asignacion timestamptz NOT NULL DEFAULT now(),
  fecha_liberacion timestamptz
);
CREATE TABLE IF NOT EXISTS public.auditoria (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id uuid,
  accion text,
  tabla_afectada text,
  registro_id uuid,
  estado_anterior jsonb,
  estado_nuevo jsonb,
  created_at timestamptz DEFAULT now()
);
-- RLS activo desde el inicio (las políticas por finca las define 00002).
ALTER TABLE public.fincas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.unidades_espaciales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.animales ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.codigos_qr ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.historial_qr ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.auditoria ENABLE ROW LEVEL SECURITY;
