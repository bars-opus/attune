import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { mergePreviews, oembedEndpoint, parseOembed } from "./oembed.ts";

const q = (u: string) => encodeURIComponent(u);

Deno.test("YouTube links of every shape go to YouTube's oEmbed", () => {
  for (
    const u of [
      "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
      "https://youtube.com/shorts/abc123",
      "https://m.youtube.com/watch?v=dQw4w9WgXcQ",
      "https://music.youtube.com/watch?v=dQw4w9WgXcQ",
      "https://youtu.be/dQw4w9WgXcQ",
    ]
  ) {
    assertEquals(oembedEndpoint(u), `https://www.youtube.com/oembed?format=json&url=${q(u)}`, u);
  }
});

Deno.test("the other inspiration sites with free oEmbed go to theirs", () => {
  const cases: [string, string][] = [
    ["https://www.tiktok.com/@chef/video/7300000000000000000", "https://www.tiktok.com/oembed?url="],
    ["https://vm.tiktok.com/ZMabc/", "https://www.tiktok.com/oembed?url="],
    ["https://vimeo.com/76979871", "https://vimeo.com/api/oembed.json?url="],
    ["https://open.spotify.com/playlist/37i9dQZF1DX", "https://open.spotify.com/oembed?url="],
    ["https://soundcloud.com/artist/track", "https://soundcloud.com/oembed?format=json&url="],
    ["https://www.reddit.com/r/travel/comments/abc/title/", "https://www.reddit.com/oembed?url="],
  ];
  for (const [u, prefix] of cases) assertEquals(oembedEndpoint(u), `${prefix}${q(u)}`, u);
});

Deno.test("Instagram uses Meta's oEmbed only when a token is configured", () => {
  const u = "https://www.instagram.com/p/C0abc/";
  assertEquals(oembedEndpoint(u), null);
  assertEquals(
    oembedEndpoint(u, "app|secret"),
    `https://graph.facebook.com/v19.0/instagram_oembed?url=${q(u)}&fields=title,author_name,thumbnail_url&access_token=${q("app|secret")}`,
  );
});

Deno.test("look-alike hosts and other sites get no endpoint", () => {
  for (const u of ["https://notyoutube.com/watch?v=1", "https://youtube.com.evil.example/x", "https://villa.example/", "nonsense"]) {
    assertEquals(oembedEndpoint(u), null, u);
  }
});

Deno.test("an oEmbed answer becomes a preview: title, author as the line under it, thumbnail", () => {
  const p = parseOembed(JSON.stringify({
    title: "Ubud &amp; rice <b>terraces</b>",
    author_name: "Travel Tom",
    thumbnail_url: "https://i.ytimg.com/vi/x/hqdefault.jpg",
  }));
  assertEquals(p, {
    title: "Ubud & rice terraces",
    description: "Travel Tom",
    imageUrl: "https://i.ytimg.com/vi/x/hqdefault.jpg",
    oembedUrl: null,
  });
});

Deno.test("untrusted oEmbed is sanitised like page tags", () => {
  const p = parseOembed(JSON.stringify({ title: "x".repeat(400), thumbnail_url: "javascript:alert(1)", author_name: 7 }));
  assertEquals(p.title!.length, 200);
  assertEquals(p.imageUrl, null);
  assertEquals(p.description, null);
  assertEquals(parseOembed("not json"), { title: null, description: null, imageUrl: null, oembedUrl: null });
  assertEquals(parseOembed("[1,2]").title, null);
});

Deno.test("with no title, the author stands in for it", () => {
  const p = parseOembed(JSON.stringify({ author_name: "@chef", thumbnail_url: "https://p16.tiktokcdn.com/a.jpg" }));
  assertEquals(p.title, "@chef");
  assertEquals(p.description, null);
});

Deno.test("merging fills what the first preview is missing from the second", () => {
  const page = { title: "Pin", description: null, imageUrl: null, oembedUrl: "https://www.pinterest.com/oembed.json?url=x" };
  const o = { title: "Better", description: "by Ann", imageUrl: "https://i.pinimg.com/a.jpg", oembedUrl: null };
  assertEquals(mergePreviews(page, o), {
    title: "Pin",
    description: "by Ann",
    imageUrl: "https://i.pinimg.com/a.jpg",
    oembedUrl: "https://www.pinterest.com/oembed.json?url=x",
  });
});
