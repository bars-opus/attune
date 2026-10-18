// Sync audit M-5: a deleted message or a system notice ("Goal reached:
// <plan>") is never pushed; Spec 1b keeps plan titles off lock screens.
import { assertEquals } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { messagePushable } from "./index.ts";

Deno.test("only live, ordinary messages are pushed", () => {
  assertEquals(messagePushable({ deleted_at: null, is_system_notice: false }), true);
  assertEquals(messagePushable({ deleted_at: "2026-10-18T00:00:00Z", is_system_notice: false }), false);
  assertEquals(messagePushable({ deleted_at: null, is_system_notice: true }), false);
});

Deno.test("the worker checks it before any push", async () => {
  const src = await Deno.readTextFile(new URL("./index.ts", import.meta.url));
  const body = src.slice(src.indexOf('.from("messages")'));
  const check = body.indexOf("messagePushable(");
  if (check < 0 || check > body.indexOf("chat_message_preview_enabled")) {
    throw new Error("messagePushable is not checked before the push settings");
  }
});
