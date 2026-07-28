// supabase/functions/generate-resolution/index.ts
//
// Deployed as: supabase functions deploy generate-resolution
// Requires secret: supabase secrets set OPENROUTER_API_KEY=sk-or-v1-xxxxxxxx
//
// This function runs server-side, so the OpenRouter key never reaches the browser.
// It receives an agenda title (+ optional existing notes) from minutes.html and
// returns a formal resolution string generated via an OpenRouter free model.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const OPENROUTER_API_KEY = Deno.env.get("OPENROUTER_API_KEY");
const OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions";

// "openrouter/free" auto-routes to whichever free model is currently healthy,
// which protects you from individual :free model IDs rotating out without notice.
const MODEL = "openrouter/free";

const RESOLUTION_SYSTEM_PROMPT = `Based only on the provided Agenda item, generate a formal, concise, and professional Resolution (Decision) suitable for official meeting minutes. The resolution should clearly state the decision taken using standard minute-writing language such as "It was resolved that...", "It was unanimously resolved that...", or "It was decided that...", as appropriate. If the agenda implies assigning responsibilities, include the responsible person, committee, or department and any relevant follow-up action or timeline when it can be reasonably inferred. Do not invent facts, dates, amounts, names, or decisions that are not supported by the agenda. If the agenda is purely for discussion or information sharing, write a resolution reflecting that the matter was discussed, noted, or deferred rather than assuming approval. Return only the resolution text without headings, numbering, explanations, or quotation marks, using clear, formal language suitable for direct insertion into the Resolution field of the meeting minutes form.`;

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  // Browser preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  if (!OPENROUTER_API_KEY) {
    return new Response(
      JSON.stringify({ error: "Server misconfigured: OPENROUTER_API_KEY secret not set." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }

  try {
    const { agendaTitle, agendaNotes } = await req.json();
    const title = (agendaTitle || "").toString().trim();

    if (!title) {
      return new Response(JSON.stringify({ error: "agendaTitle is required." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const notes = (agendaNotes || "").toString().trim();
    const userContent = notes
      ? `Agenda item: ${title}\n\nExisting notes (optional context, not to be treated as final wording): ${notes}`
      : `Agenda item: ${title}`;

    const upstream = await fetch(OPENROUTER_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${OPENROUTER_API_KEY}`,
        "Content-Type": "application/json",
        // Recommended by OpenRouter for attribution / rate-limit fairness on free models
        "HTTP-Referer": "https://nabinchalise.com.np",
        "X-Title": "Rotaract Meeting Minutes - Resolution Generator",
      },
      body: JSON.stringify({
        model: MODEL,
        messages: [
          { role: "system", content: RESOLUTION_SYSTEM_PROMPT },
          { role: "user", content: userContent },
        ],
        temperature: 0.4,
      }),
    });

    if (!upstream.ok) {
      const detail = await upstream.text();
      console.error("OpenRouter error:", upstream.status, detail);
      return new Response(
        JSON.stringify({ error: `AI provider returned ${upstream.status}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const data = await upstream.json();
    let resolutionText: string | undefined = data?.choices?.[0]?.message?.content?.trim();

    if (!resolutionText) {
      return new Response(JSON.stringify({ error: "Empty response from AI provider." }), {
        status: 502,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Strip stray surrounding quotes if the model added them
    resolutionText = resolutionText.replace(/^["']|["']$/g, "").trim();

    return new Response(JSON.stringify({ resolution: resolutionText }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("generate-resolution error:", err);
    return new Response(JSON.stringify({ error: "Unexpected server error." }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});
