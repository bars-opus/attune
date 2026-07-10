export async function sendOneSignalPush(input: {
  userId: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  idempotencyKey?: string;
}) {
  const appId = requiredEnv("ONESIGNAL_APP_ID");
  const apiKey = requiredEnv("ONESIGNAL_API_KEY");
  const response = await fetch("https://api.onesignal.com/notifications", {
    method: "POST",
    headers: {
      "Authorization": `Key ${apiKey}`,
      "Content-Type": "application/json",
      ...(input.idempotencyKey
        ? { "Idempotency-Key": input.idempotencyKey }
        : {}),
    },
    body: JSON.stringify({
      app_id: appId,
      include_aliases: { external_id: [input.userId] },
      target_channel: "push",
      headings: { en: input.title },
      contents: { en: input.body },
      data: input.data ?? {},
    }),
  });

  if (!response.ok) {
    throw new Error(`onesignal_${response.status}`);
  }
  const result = await response.json().catch(() => ({}));
  return typeof result.id === "string" ? result.id : null;
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`missing_${name.toLowerCase()}`);
  return value;
}
