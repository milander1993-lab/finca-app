// ia-asistente — Servicio de IA contextual y auxiliar (Prompt Maestro §60, D-015, 3.9).
// - Lee SOLO lo que el usuario puede ver (usa el JWT del usuario: RLS por finca).
// - Nunca escribe datos críticos: solo registra la interacción en ia_interacciones.
// - No calcula (D-016): explica cálculos del motor determinístico.
// - Proveedor desacoplado: hoy Anthropic (variable ANTHROPIC_API_KEY). Sin clave → responde
//   "IA no configurada" y la app sigue funcionando sin IA.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (cuerpo: unknown, estado = 200) =>
  new Response(JSON.stringify(cuerpo), { status: estado, headers: { ...cors, "Content-Type": "application/json" } });

const SISTEMA = `Eres el asistente del "Sistema Agroecológico Integral" de una finca ganadera y agroecológica en Caquetá, Colombia.
Respondes en español sencillo, breve y concreto, a un productor.
Reglas obligatorias (no negociables):
1. Nunca inventes datos ni valores. Usa solo el CONTEXTO entregado. Si algo no está, di "sin datos" o "no disponible".
2. Distingue siempre la naturaleza del dato: observado, medido, estimado, calculado, externo/modelado, pronosticado, validado.
3. No presentes una estimación como medición, una observación como diagnóstico profesional, una hipótesis como hecho,
   ni una correlación como causa. Una alerta indica que algo requiere revisión, no demuestra la causa.
4. No calculas: los cálculos los hace el motor determinístico de la app. Puedes explicar cómo se calculan.
5. Una recomendación no es una decisión: el humano decide. No ordenes acciones sensibles (sanitarias, económicas, legales).
6. En sanidad, sugiere consultar a un profesional cuando corresponda.
7. Termina SIEMPRE con dos líneas: "Datos consultados: ..." e "Incertidumbre: ...".`;

const PLANTILLAS: Record<string, string> = {
  explicar: "Explica este registro y su contexto en lenguaje sencillo: qué es, en qué estado está y qué sigue según el proceso.",
  faltantes: "Señala qué información falta o está incompleta en este registro y sus relacionados, y por qué importa. No inventes valores.",
  analizar: "Analiza los datos: señales que merecen revisión, posibles inconsistencias (di 'posible inconsistencia', nunca 'dato incorrecto') y qué revisar primero. Diferencia observación, cálculo e hipótesis.",
  proponer: "Propón recomendaciones (no decisiones) con 2 o 3 alternativas sin ranking arbitrario, indicando datos usados, condiciones e incertidumbre.",
  analizar_finca: "Analiza el estado general de la finca con el tablero: qué requiere atención, qué datos faltan para decidir mejor y qué revisar esta semana.",
  explicar_guia: "Explica esta guía técnica paso a paso para un trabajador de campo. Si faltan elementos, dilo: no completes con supuestos.",
  preguntar: "Responde la pregunta del usuario usando solo el contexto.",
};

const PERMITIDAS = new Set([
  "animales", "lotes_ganaderos", "unidades_espaciales", "aforos", "pesajes", "guias",
  "fuentes_agua", "mediciones_ambientales", "muestras_suelo", "resultados_suelo", "infraestructuras", "recursos",
  "sistemas_productivos", "eventos_sanitarios", "eventos_reproductivos", "produccion_leche", "entregas_leche",
  "movimientos_economicos", "especies", "lotes_vivero", "establecimientos", "actividades", "alertas", "hallazgos",
  "recomendaciones", "alternativas", "decisiones", "aprendizajes", "observaciones", "evidencias", "incidentes_tecnicos",
  "destinos_superficie",
]);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "método no permitido" }, 405);

  let cuerpo: Record<string, unknown>;
  try {
    cuerpo = await req.json();
  } catch {
    return json({ error: "cuerpo inválido" }, 400);
  }
  const fincaId = String(cuerpo.finca_id ?? "");
  const funcion = String(cuerpo.funcion ?? "preguntar");
  const tabla = cuerpo.tabla ? String(cuerpo.tabla) : null;
  const id = cuerpo.id ? String(cuerpo.id) : null;
  const pregunta = cuerpo.pregunta ? String(cuerpo.pregunta).slice(0, 2000) : null;
  if (!UUID.test(fincaId)) return json({ error: "finca inválida" }, 400);
  if (tabla && !PERMITIDAS.has(tabla)) return json({ error: "módulo no permitido" }, 400);
  if (id && !UUID.test(id)) return json({ error: "registro inválido" }, 400);

  const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
  });

  // Membresía: si RLS no deja ver la finca, no hay contexto.
  const { data: finca } = await supa.from("fincas").select("id, nombre, mision, vision").eq("id", fincaId).maybeSingle();
  if (!finca) return json({ error: "sin permiso para esta finca" }, 403);

  const contexto: Record<string, unknown> = { finca };
  const consultados: string[] = ["fincas"];
  const leer = async (nombre: string, consulta: PromiseLike<{ data: unknown }>) => {
    const { data } = await consulta;
    contexto[nombre] = data;
    consultados.push(nombre);
  };

  if (tabla && id) {
    await leer(`registro:${tabla}`, supa.from(tabla).select("*").eq("id", id).maybeSingle());
    if (tabla === "guias") {
      await leer("guia_versiones", supa.from("guia_versiones").select("*").eq("guia_id", id).order("numero", { ascending: false }).limit(3));
    }
    if (tabla === "animales") {
      await leer("pesajes", supa.from("pesajes").select("fecha_pesaje, valor, unidad, naturaleza, metodo, estado_calidad").eq("animal_id", id).eq("is_deleted", false).order("fecha_pesaje", { ascending: false }).limit(20));
      await leer("eventos_sanitarios", supa.from("eventos_sanitarios").select("tipo, etapa, fecha_hecho, descripcion, profesional, naturaleza").eq("animal_id", id).eq("is_deleted", false).limit(20));
      await leer("eventos_reproductivos", supa.from("eventos_reproductivos").select("tipo, fecha_hecho, resultado, naturaleza").eq("animal_id", id).eq("is_deleted", false).limit(20));
      await leer("animal_lote", supa.from("animal_lote").select("lote_id, fecha_ingreso, fecha_salida, motivo_salida").eq("animal_id", id).limit(20));
    }
    if (tabla === "aforos") {
      await leer("aforo_muestras", supa.from("aforo_muestras").select("punto, area_muestra_m2, materia_fresca_g, materia_seca_g, estado_calidad").eq("aforo_id", id).eq("is_deleted", false));
      await leer("v_aforos_resumen", supa.from("v_aforos_resumen").select("*").eq("aforo_id", id).maybeSingle());
    }
    if (tabla !== "guias") {
      await leer("observaciones", supa.from("observaciones").select("fecha_hecho, texto, naturaleza").eq("objeto_tipo", tabla).eq("objeto_id", id).eq("is_deleted", false).limit(20));
      await leer("actividades_vinculadas", supa.from("actividades").select("titulo, estado, fecha_programada, resultado, verificacion").or(`and(objeto_tipo.eq.${tabla},objeto_id.eq.${id}),origen_id.eq.${id}`).eq("is_deleted", false).limit(20));
    }
  } else if (tabla) {
    await leer(`lista:${tabla}`, supa.from(tabla).select("*").eq("finca_id", fincaId).eq("is_deleted", false).order("created_at", { ascending: false }).limit(30));
  }
  if (!tabla || funcion === "analizar_finca") {
    await leer("tablero", supa.rpc("tablero_finca", { p_finca: fincaId }));
  }

  const entrada = [PLANTILLAS[funcion] ?? PLANTILLAS.preguntar, pregunta ? `Pregunta del usuario: ${pregunta}` : ""]
    .filter(Boolean).join("\n");
  const registrar = async (fila: Record<string, unknown>) => {
    const { data } = await supa.from("ia_interacciones").insert({
      finca_id: fincaId, funcion, contexto: { tabla, id }, entrada, datos_consultados: consultados, ...fila,
    }).select("id").maybeSingle();
    return (data as { id?: string } | null)?.id ?? null;
  };

  const clave = Deno.env.get("ANTHROPIC_API_KEY");
  if (!clave) {
    const interaccion_id = await registrar({ estado: "fallida", incertidumbre: "IA no configurada (proveedor pendiente, 3.9)" });
    return json({
      configurada: false,
      interaccion_id,
      mensaje: "La IA todavía no está activada: falta elegir el proveedor y guardar su clave (decisión pendiente 3.9). " +
        "Todo lo demás de la app funciona sin IA.",
      datos_consultados: consultados,
    });
  }

  const modelo = Deno.env.get("IA_MODELO") ?? "claude-haiku-4-5-20251001";
  let salida = "";
  let versionModelo = modelo;
  try {
    const r = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": clave, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: modelo,
        max_tokens: 1200,
        system: SISTEMA,
        messages: [{
          role: "user",
          content: `${entrada}\n\nCONTEXTO (datos reales de la app en JSON; lo que no aparece no existe):\n${JSON.stringify(contexto).slice(0, 60000)}`,
        }],
      }),
    });
    if (!r.ok) throw new Error(`proveedor respondió ${r.status}`);
    const out = await r.json();
    salida = (out.content ?? []).map((c: { text?: string }) => c.text ?? "").join("\n").trim();
    versionModelo = out.model ?? modelo;
  } catch (e) {
    const interaccion_id = await registrar({ estado: "fallida", modelo, incertidumbre: `Fallo del proveedor: ${String(e)}` });
    return json({ configurada: true, interaccion_id, error: "La IA no respondió. El resto de la app sigue funcionando." }, 502);
  }

  const incertidumbre = "Respuesta de IA: puede equivocarse u omitir datos; verifique antes de actuar. No es diagnóstico ni decisión.";
  const interaccion_id = await registrar({ salida, modelo, version_modelo: versionModelo, incertidumbre, estado: "registrada" });
  return json({ configurada: true, interaccion_id, salida, modelo: versionModelo, incertidumbre, datos_consultados: consultados });
});
