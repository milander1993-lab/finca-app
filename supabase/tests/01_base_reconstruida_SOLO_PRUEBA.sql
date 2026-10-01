-- SOLO PRUEBA: reconstrucción de 00001 según lo pegado por el usuario (+columnas de auditoría que faltaban)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp"; CREATE EXTENSION IF NOT EXISTS postgis;
CREATE OR REPLACE FUNCTION actualizar_timestamps() RETURNS trigger AS $$ BEGIN NEW.updated_at=NOW(); NEW.version=OLD.version+1; RETURN NEW; END $$ LANGUAGE plpgsql;
CREATE TABLE fincas (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), nombre text NOT NULL);
CREATE TABLE unidades_espaciales (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), finca_id uuid NOT NULL REFERENCES fincas(id), parent_id uuid REFERENCES unidades_espaciales(id), tipo varchar(40), nombre text, geometria geometry(Polygon,4326), es_temporal boolean DEFAULT false, estado varchar(20));
CREATE TABLE animales (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), finca_id uuid NOT NULL REFERENCES fincas(id), numero_interno varchar(40) NOT NULL, categoria varchar(30), sexo varchar(10), fecha_nacimiento date, fecha_nacimiento_naturaleza varchar(20) DEFAULT 'estimada', estado varchar(20) DEFAULT 'activo', peso_ultimo DECIMAL(8,2));
CREATE TABLE codigos_qr (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), codigo text UNIQUE NOT NULL, estado varchar(20) DEFAULT 'disponible', animal_actual_id uuid UNIQUE REFERENCES animales(id));
CREATE TABLE historial_qr (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), codigo_qr_id uuid NOT NULL REFERENCES codigos_qr(id), animal_id uuid NOT NULL REFERENCES animales(id), fecha_asignacion timestamptz NOT NULL DEFAULT now(), fecha_liberacion timestamptz);
CREATE TABLE auditoria (id uuid PRIMARY KEY DEFAULT uuid_generate_v4(), actor_id uuid, accion text, tabla_afectada text, registro_id uuid, estado_anterior jsonb, estado_nuevo jsonb, created_at timestamptz DEFAULT now());
