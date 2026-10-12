// Extracts a link preview's text from untrusted HTML: og:title (<= 200
// code points), og:description (<= 500) and og:image. Output is plain
// text -- markup removed, entities decoded, control characters stripped.

export interface ParsedPreview {
  title: string | null;
  description: string | null;
  imageUrl: string | null;
}

const NAMED: Record<string, string> = {
  amp: "&", lt: "<", gt: ">", quot: '"', apos: "'", nbsp: " ", ndash: "–", mdash: "—",
  hellip: "…", lsquo: "‘", rsquo: "’", ldquo: "“", rdquo: "”",
  copy: "©", reg: "®", trade: "™",
};

function decodeEntities(s: string): string {
  return s.replace(/&(#x[0-9a-f]{1,6}|#\d{1,7}|[a-z]{2,8});/gi, (whole, body: string) => {
    if (body[0] === "#") {
      const cp = body[1] === "x" || body[1] === "X" ? parseInt(body.slice(2), 16) : parseInt(body.slice(1), 10);
      const valid = cp > 0 && cp <= 0x10ffff && !(cp >= 0xd800 && cp <= 0xdfff);
      return valid ? String.fromCodePoint(cp) : whole;
    }
    return NAMED[body.toLowerCase()] ?? whole;
  });
}

function clean(raw: string | undefined, max: number): string | null {
  if (!raw) return null;
  const text = decodeEntities(raw.replace(/<[^>]*>/g, ""))
    .replace(/[\u0000-\u001f\u007f-\u009f​-‏‪-‮⁦-⁩]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  const capped = Array.from(text).slice(0, max).join("").trimEnd();
  return capped === "" ? null : capped;
}

function attributes(tag: string): Map<string, string> {
  const out = new Map<string, string>();
  const re = /([a-zA-Z_:.-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'>]+))/g;
  for (const m of tag.matchAll(re)) {
    const key = m[1].toLowerCase();
    if (!out.has(key)) out.set(key, m[2] ?? m[3] ?? m[4] ?? "");
  }
  return out;
}

export function parsePreview(html: string, pageUrl: string): ParsedPreview {
  const meta = new Map<string, string>();
  // Quote-aware so a ">" inside an attribute value does not end the tag.
  for (const m of html.matchAll(/<meta\b(?:[^>"']|"[^"]*"|'[^']*')*>/gi)) {
    const a = attributes(m[0]);
    const key = (a.get("property") ?? a.get("name") ?? "").toLowerCase();
    const content = a.get("content");
    if (key && content !== undefined && !meta.has(key)) meta.set(key, content);
  }
  const titleTag = /<title\b[^>]*>([\s\S]*?)<\/title>/i.exec(html)?.[1];

  let imageUrl: string | null = null;
  const rawImage = meta.get("og:image") ?? meta.get("og:image:url") ?? meta.get("twitter:image");
  if (rawImage) {
    try {
      const u = new URL(decodeEntities(rawImage.trim()), pageUrl);
      if ((u.protocol === "http:" || u.protocol === "https:") && u.href.length <= 2048) imageUrl = u.href;
    } catch {
      imageUrl = null;
    }
  }

  return {
    title: clean(meta.get("og:title") ?? meta.get("twitter:title") ?? titleTag, 200),
    description: clean(meta.get("og:description") ?? meta.get("twitter:description") ?? meta.get("description"), 500),
    imageUrl,
  };
}
