// Spec 1 W2c: Standard Webhooks signatures (Auth's HTTP hooks).
import { verifyStandardWebhook } from "./standard_webhooks.ts";

// The published test vector.
const SECRET = "v1,whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw";
const BODY = '{"test": 2432232314}';
const headers = (signature: string, timestamp = "1614265330") =>
  new Headers({
    "webhook-id": "msg_p5jXN8AQM9LWM0D4loKWxJek",
    "webhook-timestamp": timestamp,
    "webhook-signature": signature,
  });
const GOOD = "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE=";

Deno.test("the published vector verifies, alone or among others", async () => {
  if (!(await verifyStandardWebhook(SECRET, headers(GOOD), BODY, 1614265330))) {
    throw new Error("the vector failed");
  }
  if (!(await verifyStandardWebhook(SECRET, headers(`v1,AAAA ${GOOD}`), BODY, 1614265330))) {
    throw new Error("a second signature was ignored");
  }
});

Deno.test("a changed body, a wrong secret, an old timestamp or no header fails", async () => {
  const checks: [string, Promise<boolean>][] = [
    ["body", verifyStandardWebhook(SECRET, headers(GOOD), '{"test": 1}', 1614265330)],
    ["secret", verifyStandardWebhook("v1,whsec_AAAAAAAAAAAAAAAAAAAAAAAA", headers(GOOD), BODY, 1614265330)],
    ["too old", verifyStandardWebhook(SECRET, headers(GOOD), BODY, 1614265330 + 301)],
    ["no signature", verifyStandardWebhook(SECRET, new Headers(), BODY, 1614265330)],
    ["wrong version", verifyStandardWebhook(SECRET, headers(GOOD.replace("v1,", "v2,")), BODY, 1614265330)],
  ];
  for (const [what, check] of checks) {
    if (await check) throw new Error(`${what}: verified`);
  }
});

// Supabase Auth signs with every configured secret and joins the entries
// with ", " (supabase/auth internal/hooks/hookshttp: strings.Join(
// signatureList, ", ")), so during a secret rotation an entry ends with a
// comma. Ours must verify in either position.
Deno.test("Auth's comma-joined signatures verify in either position", async () => {
  for (const header of [`${GOOD}, v1,AAAA`, `v1,AAAA, ${GOOD}`]) {
    if (!(await verifyStandardWebhook(SECRET, headers(header), BODY, 1614265330))) {
      throw new Error(`not verified: ${header}`);
    }
  }
  if (await verifyStandardWebhook(SECRET, headers(`${GOOD.slice(0, -2)}, v1,AAAA`), BODY, 1614265330)) {
    throw new Error("a cut signature verified");
  }
});
