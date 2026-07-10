import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const CLAUDE_API_KEY = Deno.env.get("CLAUDE_API_KEY");
const CLAUDE_URL = "https://api.anthropic.com/v1/messages";

type ReflectionType = "chapter" | "journey";

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { journey_id, chapter, type } = await req.json() as {
      journey_id?: string;
      chapter?: number;
      type?: ReflectionType;
    };

    if (!journey_id || (type !== "chapter" && type !== "journey")) {
      return json({ error: "Invalid reflection request" }, 400);
    }

    if (type === "chapter" && ![1, 2, 3].includes(chapter ?? 0)) {
      return json({ error: "Invalid chapter" }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: journey } = await supabase
      .from("thirty_six_question_journeys")
      .select("*")
      .eq("id", journey_id)
      .single();

    if (!journey) return json({ error: "Journey not found" }, 404);

    if (type === "journey") {
      const complete = journey.chapter_1_completed_at &&
        journey.chapter_2_completed_at &&
        journey.chapter_3_completed_at;
      if (!complete) return json({ observation: null, confidence: "low" });
    }

    const chapters = type === "chapter" ? [chapter!] : [1, 2, 3];
    const usable = await loadUsableAnswers(supabase, journey_id, chapters);

    const totalAnswers = usable.answers.length;
    const perPartner = countPerPartner(usable.answers);
    const partnerA = usable.relationship?.user_a;
    const partnerB = usable.relationship?.user_b;
    const partnerACount = partnerA ? perPartner[partnerA] ?? 0 : 0;
    const partnerBCount = partnerB ? perPartner[partnerB] ?? 0 : 0;

    const eligible = type === "chapter"
      ? totalAnswers >= 8 && partnerACount >= 3 && partnerBCount >= 3
      : totalAnswers >= 24 && partnerACount >= 6 && partnerBCount >= 6;

    if (!eligible) {
      return json({
        observation: null,
        confidence: "low",
        message: "Not enough usable answers",
      });
    }

    if (!CLAUDE_API_KEY) {
      return json({
        observation: null,
        confidence: "low",
        message: "Claude API key is not configured",
      });
    }

    const prompt = buildPrompt(
      usable.rounds,
      usable.answers,
      usable.relationship,
    );
    const result = await generateReflection(prompt, type);

    const sourceAnswerIds = usable.answers.map(
      (answer: { id: string }) => answer.id,
    );

    if (type === "chapter") {
      await supabase
        .from("chapter_reflections")
        .upsert({
          journey_id,
          chapter,
          observation: result.observation,
          confidence: result.confidence,
          source_answer_ids: sourceAnswerIds,
          is_hidden: false,
          generated_at: new Date().toISOString(),
        }, { onConflict: "journey_id,chapter" });
    } else {
      await supabase
        .from("thirty_six_question_journeys")
        .update({
          final_observation: result.observation,
          final_observation_confidence: result.confidence,
          final_source_answer_ids: sourceAnswerIds,
          final_observation_hidden: false,
          updated_at: new Date().toISOString(),
        })
        .eq("id", journey_id);
    }

    return json(result);
  } catch (error) {
    console.error("generate-thirty-six-reflection error:", error);
    return json({ error: errorMessage(error) }, 500);
  }
});

async function loadUsableAnswers(
  supabase: any,
  journeyId: string,
  chapters: number[],
) {
  const { data: sessions } = await supabase
    .from("game_sessions")
    .select("id, relationship_id, chapter")
    .eq("journey_id", journeyId)
    .eq("game_type", "36_questions")
    .eq("status", "completed")
    .in("chapter", chapters);

  const sessionIds = (sessions ?? []).map((session: any) => session.id);
  const relationshipId = sessions?.[0]?.relationship_id;

  const { data: relationship } = relationshipId
    ? await supabase
      .from("relationships")
      .select("user_a, user_b")
      .eq("id", relationshipId)
      .single()
    : { data: null };

  if (sessionIds.length === 0) {
    return { rounds: [], answers: [], relationship };
  }

  const { data: rounds } = await supabase
    .from("game_session_rounds")
    .select("id, session_id, round_number, question_text_snapshot")
    .in("session_id", sessionIds)
    .order("round_number", { ascending: true });

  const roundIds = (rounds ?? []).map((round: any) => round.id);
  if (roundIds.length === 0) {
    return { rounds: [], answers: [], relationship };
  }

  const { data: answers } = await supabase
    .from("thirty_six_question_answers")
    .select("id, round_id, user_id, answer_text")
    .in("round_id", roundIds)
    .eq("is_removed", false)
    .eq("is_safety_triggered", false)
    .eq("is_excluded_from_ai", false);

  return { rounds: rounds ?? [], answers: answers ?? [], relationship };
}

function countPerPartner(answers: any[]) {
  return answers.reduce((acc: Record<string, number>, answer) => {
    acc[answer.user_id] = (acc[answer.user_id] ?? 0) + 1;
    return acc;
  }, {});
}

function buildPrompt(rounds: any[], answers: any[], relationship: any) {
  const answersByRound: Record<string, Record<string, string>> = {};
  for (const answer of answers) {
    answersByRound[answer.round_id] ??= {};
    answersByRound[answer.round_id][answer.user_id] = answer.answer_text;
  }

  let prompt = "";
  for (const round of rounds) {
    const roundAnswers = answersByRound[round.id];
    if (!roundAnswers) continue;
    const userAAnswer = roundAnswers[relationship.user_a];
    const userBAnswer = roundAnswers[relationship.user_b];
    if (!userAAnswer || !userBAnswer) continue;

    prompt += `Question: ${round.question_text_snapshot}\n`;
    prompt += `Partner A: ${userAAnswer}\n`;
    prompt += `Partner B: ${userBAnswer}\n\n`;
  }
  return prompt;
}

async function generateReflection(prompt: string, type: ReflectionType) {
  const systemPrompt = `
ABSOLUTE CONSTRAINTS:
1. Never use clinical language.
2. Never diagnose either partner or the relationship.
3. Never assign blame.
4. Never use the words toxic, narcissist, codependent, disorder, or broken.
5. Never invent a theme that is not clearly supported by the answers.
6. Speak to "you both" or "your answers", not to named partners.
7. Return only valid JSON.

Return:
{
  "observation": string | null,
  "confidence": "high" | "medium" | "low"
}
  `;

  const userPrompt = `
You are reviewing partners' answers to a structured relationship conversation.
Find one grounded theme, connection, or gentle contrast across the answers.
${type === "chapter" ? "Use at most 25 words." : "Use 50 to 60 words."}

${prompt}
  `;

  const response = await fetch(CLAUDE_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": CLAUDE_API_KEY!,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-3-5-sonnet-20241022",
      max_tokens: 220,
      system: systemPrompt,
      messages: [{ role: "user", content: userPrompt }],
    }),
    signal: AbortSignal.timeout(10000),
  });

  if (!response.ok) {
    console.error("Claude API failed:", response.status, await response.text());
    return { observation: null, confidence: "low" };
  }

  const data = await response.json();
  const text = data.content?.[0]?.text ?? "{}";
  const parsed = JSON.parse(text.replace(/```json|```/g, "").trim());

  return {
    observation: parsed.observation ?? null,
    confidence: ["high", "medium", "low"].includes(parsed.confidence)
      ? parsed.confidence
      : "low",
  };
}

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "Unknown error";
}
