// Spec 1 W7b (B5 M6): no production function reaches the stub matcher
// except through the seam. stubMatcher answers clear for almost any bytes
// and knows nothing of the production refusal; only matcherFromEnv (in
// _shared/csam_matcher.ts) may build it, after both PF-H1 checks. Tests
// may import it. scan-media builds its matcher with matcherFromEnv.
function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const functionsRoot = new URL("../", import.meta.url);
const SEAM = "_shared/csam_matcher.ts";

async function productionSources(dir: URL, prefix = ""): Promise<string[]> {
  const found: string[] = [];
  for await (const entry of Deno.readDir(dir)) {
    const rel = `${prefix}${entry.name}`;
    if (entry.isDirectory) {
      if (entry.name === "node_modules" || entry.name === "testdata") continue;
      found.push(...await productionSources(new URL(`${entry.name}/`, dir), `${rel}/`));
    } else if (/\.(ts|tsx|js|mjs)$/.test(entry.name) && !/[._]test\.(ts|tsx|js|mjs)$/.test(entry.name)) {
      found.push(rel);
    }
  }
  return found;
}

Deno.test("B5 M6: only the seam names stubMatcher; scan-media uses matcherFromEnv", async () => {
  const sources = await productionSources(functionsRoot);
  assert(sources.includes(SEAM) && sources.includes("scan-media/index.ts"), `walked ${sources.length} files`);
  const offenders: string[] = [];
  for (const rel of sources) {
    if (rel === SEAM) continue;
    const text = await Deno.readTextFile(new URL(rel, functionsRoot));
    if (/\bstubMatcher\b/.test(text)) offenders.push(rel);
  }
  assert(offenders.length === 0, `stubMatcher named outside the seam: ${offenders.join(", ")}`);
  const index = await Deno.readTextFile(new URL("scan-media/index.ts", functionsRoot));
  assert(/\bmatcherFromEnv\(/.test(index), "scan-media/index.ts does not build its matcher with matcherFromEnv");
});
