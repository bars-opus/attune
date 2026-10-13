// oEmbed: the endpoints sites publish so others can preview their links.
// Video and social sites (YouTube, TikTok, Instagram…) do not put preview
// tags in the page a server gets, so for them this is the only reliable
// source of a title and thumbnail. Every fetch still goes through guard.ts.

import { clean, httpUrl, type ParsedPreview } from "./og.ts";

interface Provider {
  /// The site's own hosts, exactly or as a parent domain.
  hosts: string[];
  endpoint: (url: string) => string;
}

const q = encodeURIComponent;

const PROVIDERS: Provider[] = [
  { hosts: ["youtube.com", "youtu.be"], endpoint: (u) => `https://www.youtube.com/oembed?format=json&url=${q(u)}` },
  { hosts: ["tiktok.com"], endpoint: (u) => `https://www.tiktok.com/oembed?url=${q(u)}` },
  { hosts: ["vimeo.com"], endpoint: (u) => `https://vimeo.com/api/oembed.json?url=${q(u)}` },
  { hosts: ["spotify.com"], endpoint: (u) => `https://open.spotify.com/oembed?url=${q(u)}` },
  { hosts: ["soundcloud.com"], endpoint: (u) => `https://soundcloud.com/oembed?format=json&url=${q(u)}` },
  { hosts: ["reddit.com", "redd.it"], endpoint: (u) => `https://www.reddit.com/oembed?url=${q(u)}` },
];

/// Instagram's only oEmbed is Meta's, which needs an app access token.
const INSTAGRAM = ["instagram.com", "instagr.am"];

const onHost = (host: string, domains: string[]) =>
  domains.some((d) => host === d || host.endsWith(`.${d}`));

/// The oEmbed endpoint for [url], or null when the site has none we use.
export function oembedEndpoint(url: string, metaToken?: string): string | null {
  let host: string;
  try {
    host = new URL(url).hostname.toLowerCase();
  } catch {
    return null;
  }
  if (onHost(host, INSTAGRAM)) {
    return metaToken
      ? `https://graph.facebook.com/v19.0/instagram_oembed?url=${q(url)}` +
        `&fields=title,author_name,thumbnail_url&access_token=${q(metaToken)}`
      : null;
  }
  return PROVIDERS.find((p) => onHost(host, p.hosts))?.endpoint(url) ?? null;
}

const EMPTY: ParsedPreview = { title: null, description: null, imageUrl: null, oembedUrl: null };

/// An oEmbed answer as a preview: its title, its author as the line under
/// it, and its thumbnail. Untrusted, so cleaned exactly like page tags.
export function parseOembed(body: string): ParsedPreview {
  let json: unknown;
  try {
    json = JSON.parse(body);
  } catch {
    return EMPTY;
  }
  if (!json || typeof json !== "object" || Array.isArray(json)) return EMPTY;
  const o = json as Record<string, unknown>;
  const text = (v: unknown, max: number) => (typeof v === "string" ? clean(v, max) : null);
  const title = text(o.title, 200);
  const author = text(o.author_name, 500);
  return {
    title: title ?? author,
    description: title ? author : null,
    imageUrl: typeof o.thumbnail_url === "string" ? httpUrl(o.thumbnail_url) : null,
    oembedUrl: null,
  };
}

/// [first], with anything it is missing taken from [second].
export function mergePreviews(first: ParsedPreview, second: ParsedPreview): ParsedPreview {
  return {
    title: first.title ?? second.title,
    description: first.description ?? second.description,
    imageUrl: first.imageUrl ?? second.imageUrl,
    oembedUrl: first.oembedUrl ?? second.oembedUrl,
  };
}
