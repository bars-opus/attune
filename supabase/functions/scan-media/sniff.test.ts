// Spec 1 W7b (B4 I-3): scan-media decides image, video or other from the
// bytes' signature, never from the mime the client declared. An image
// signature anywhere it could be read as one wins (it is scanned); only a
// file that is positively a video is a video; anything else is other.
import { sniffMedia } from "./sniff.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

const enc = new TextEncoder();

function cat(...parts: (number[] | string)[]): Uint8Array {
  const chunks = parts.map((p) => (typeof p === "string" ? enc.encode(p) : Uint8Array.from(p)));
  const out = new Uint8Array(chunks.reduce((n, c) => n + c.length, 0));
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.length;
  }
  return out;
}

const ftyp = (major: string, ...compatible: string[]) => {
  const body = `ftyp${major}\0\0\0\0${compatible.join("")}`;
  return cat([0, 0, 0, 4 + body.length], body);
};

const label = (bytes: Uint8Array) => {
  const s = sniffMedia(bytes);
  return s.kind === "other" ? `other:${s.reason}` : `${s.kind}:${s.mime}`;
};

Deno.test("image signatures", () => {
  const cases: [Uint8Array, string][] = [
    [cat([0xff, 0xd8, 0xff, 0xdb]), "image:image/jpeg"],
    [cat([0xff, 0xd8, 0xff]), "image:image/jpeg"],
    [cat([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), "image:image/png"],
    [cat("GIF87a"), "image:image/gif"],
    [cat("GIF89a", [0, 0]), "image:image/gif"],
    [cat("RIFF", [1, 2, 3, 4], "WEBP"), "image:image/webp"],
    [ftyp("heic", "mif1heic"), "image:image/heic"],
    [ftyp("heix"), "image:image/heic"],
    [ftyp("hevc", "msf1hevc"), "image:image/heic"],
    [ftyp("mif1", "mif1"), "image:image/heif"],
    [ftyp("msf1"), "image:image/heif"],
    [ftyp("heif"), "image:image/heif"],
    [ftyp("avif", "mif1avif"), "image:image/avif"],
    // An image brand among the compatible ones is scanned, whatever the major.
    [ftyp("mp42", "isommif1"), "image:image/heif"],
    [cat("BM", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [40, 0, 0, 0]), "image:image/bmp"],
    [cat("BM", [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [124, 0, 0, 0]), "image:image/bmp"],
    [cat("II*", [0]), "image:image/tiff"],
    [cat("MM", [0], "*"), "image:image/tiff"],
  ];
  for (const [bytes, want] of cases) assert(label(bytes) === want, `${want}: got ${label(bytes)}`);
});

Deno.test("video signatures", () => {
  const cases: [Uint8Array, string][] = [
    [ftyp("isom", "isomiso2avc1mp41"), "video:video/mp4"],
    [ftyp("mp42"), "video:video/mp4"],
    [ftyp("qt  ", "qt  "), "video:video/quicktime"],
    [ftyp("3gp5"), "video:video/mp4"],
    [cat([0, 0, 0, 8], "moov"), "video:video/quicktime"],
    [cat([0, 0, 0, 8], "mdat"), "video:video/quicktime"],
    [cat([0, 0, 0, 8], "wide"), "video:video/quicktime"],
    [cat([0x1a, 0x45, 0xdf, 0xa3]), "video:video/webm"],
  ];
  for (const [bytes, want] of cases) assert(label(bytes) === want, `${want}: got ${label(bytes)}`);
});

Deno.test("anything else is other, with a reason", () => {
  const cases: [Uint8Array, string][] = [
    [new Uint8Array(0), "other:empty_object"],
    [cat([0xff, 0xd8]), "other:not_image_or_video"],
    [cat("GIF8"), "other:not_image_or_video"],
    [cat("GIF90a"), "other:not_image_or_video"],
    [cat("RIFF", [1, 2, 3, 4], "WAVE"), "other:not_image_or_video"],
    [cat("BM and then some ordinary text"), "other:not_image_or_video"],
    [cat("II", [0, 0]), "other:not_image_or_video"],
    [ftyp("M4A ", "M4A mp42isom"), "other:not_image_or_video"],
    [ftyp("M4B "), "other:not_image_or_video"],
    [cat([0, 0, 0, 8], "ftyp"), "other:not_image_or_video"],
    [cat("%PDF-1.7"), "other:not_image_or_video"],
    [cat("just some text"), "other:not_image_or_video"],
    [cat([0x49, 0x44, 0x33, 4, 0]), "other:not_image_or_video"],
  ];
  for (const [bytes, want] of cases) assert(label(bytes) === want, `${want}: got ${label(bytes)}`);
});

Deno.test("a brand list is read only inside its own box, and never past the bytes", () => {
  // The box says 16 bytes: the trailing "heic" is outside it, so this is a video.
  const outside = cat([0, 0, 0, 16], "ftypisom", [0, 0, 0, 0], "heic");
  assert(label(outside) === "video:video/mp4", label(outside));
  // A box size larger than the file is read up to the end only.
  const short = cat([0x7f, 0xff, 0xff, 0xff], "ftypisom", [0, 0, 0, 0], "mif1");
  assert(label(short) === "image:image/heif", label(short));
});

Deno.test("M-4: an ftyp box of size 0 or 1 still has its brand list read", () => {
  // Size 0: the box runs to the end of the file.
  const toEnd = cat([0, 0, 0, 0], "ftypmp42", [0, 0, 0, 0], "isommif1");
  assert(label(toEnd) === "image:image/heif", label(toEnd));
  // Size 1: a 64-bit size follows the type; the brands start 8 bytes later.
  const large = cat([0, 0, 0, 1], "ftyp", [0, 0, 0, 0, 0, 0, 0, 32], "mp42", [0, 0, 0, 0], "isomheic");
  assert(label(large) === "image:image/heic", label(large));
  const largeVideo = cat([0, 0, 0, 1], "ftyp", [0, 0, 0, 0, 0, 0, 0, 24], "isom", [0, 0, 0, 0]);
  assert(label(largeVideo) === "video:video/mp4", label(largeVideo));
  // A 64-bit size whose brand list is outside it is not read.
  const outside = cat([0, 0, 0, 1], "ftyp", [0, 0, 0, 0, 0, 0, 0, 24], "isom", [0, 0, 0, 0], "heic");
  assert(label(outside) === "video:video/mp4", label(outside));
  const tooShort = cat([0, 0, 0, 1], "ftyp", [0, 0, 0, 0]);
  assert(label(tooShort) === "other:not_image_or_video", label(tooShort));
});

Deno.test("M-4: ICO and CUR are images (Skia draws them; an ICO may hold a PNG)", () => {
  assert(label(cat([0, 0, 1, 0, 1, 0], [16, 16, 0, 0])) === "image:image/x-icon", "ico");
  assert(label(cat([0, 0, 2, 0, 2, 0], [32, 32, 0, 0])) === "image:image/x-icon", "cur");
  assert(label(cat([0, 0, 1, 0, 0, 0])) === "other:not_image_or_video", "an icon file with no images");
  assert(label(cat([0, 0, 1, 0])) === "other:not_image_or_video", "too short for an icon header");
  assert(label(cat([0, 0, 1, 0xba, 0x44, 0])) === "other:not_image_or_video", "an MPEG pack header is not an icon");
  // A 256-byte ftyp box starts like an icon; it is read as what it is.
  const box256 = cat([0, 0, 1, 0], "ftypisom", [0, 0, 0, 0], "isom".repeat(60));
  assert(label(box256) === "video:video/mp4", label(box256));
});
