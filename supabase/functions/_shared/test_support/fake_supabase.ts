// TEST-ONLY. A supabase-js-shaped fake for handler tests (Spec 1 W9e):
// every chain is recorded (table, operation, filters, payload) and
// [answer] decides what a finished chain resolves to. It never reaches a
// network or a database.

export type FakeCall = {
  table: string;
  op: "" | "select" | "delete" | "update" | "upsert" | "insert";
  filters: Array<[string, string, unknown]>;
  payload?: unknown;
};

export type FakeAnswer = { data: unknown; error: unknown };

export function fakeClient(answer: (call: FakeCall) => FakeAnswer | Promise<FakeAnswer> = () => ({ data: null, error: null })) {
  const calls: FakeCall[] = [];
  const rpcs: Array<{ fn: string; params: Record<string, unknown> }> = [];
  function chain(call: FakeCall) {
    const done = () => Promise.resolve(answer(call));
    const filter = (kind: string) => (col: string, v?: unknown) => {
      call.filters.push([kind, col, v]);
      return c;
    };
    const c: Record<string, unknown> = {
      select(_cols?: string) {
        if (call.op === "") call.op = "select";
        return c;
      },
      delete() {
        call.op = "delete";
        return c;
      },
      update(payload: unknown) {
        call.op = "update";
        call.payload = payload;
        return c;
      },
      upsert(payload: unknown, _opts?: unknown) {
        call.op = "upsert";
        call.payload = payload;
        return c;
      },
      insert(payload: unknown) {
        call.op = "insert";
        call.payload = payload;
        return c;
      },
      eq: filter("eq"),
      neq: filter("neq"),
      is: filter("is"),
      in: filter("in"),
      order: filter("order"),
      limit: (n: number) => {
        call.filters.push(["limit", "", n]);
        return c;
      },
      single: done,
      maybeSingle: done,
      then(resolve: (v: unknown) => unknown, reject: (e: unknown) => unknown) {
        return done().then(resolve, reject);
      },
    };
    return c;
  }
  return {
    calls,
    rpcs,
    client: {
      from(table: string) {
        const call: FakeCall = { table, op: "", filters: [] };
        calls.push(call);
        return chain(call);
      },
      rpc(fn: string, params: Record<string, unknown>) {
        rpcs.push({ fn, params });
        return Promise.resolve({ data: null, error: null });
      },
    },
  };
}
