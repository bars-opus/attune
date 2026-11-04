// supabase/functions/scan-media/sniff.ts
//
// Spec 1 W7b (B4 I-3): what an object is, read from its first bytes. The
// mime on the queue row is whatever the uploading client declared, so it
// is never trusted: every object in a scanned bucket is queued, and this
// decides. Images: JPEG, PNG, GIF, WebP, HEIC/HEIF (and AVIF, BMP, TIFF,
// ICO/CUR, which are images too: an image read as "other" would be skipped
// unscanned; B6 M-4). Videos: MP4, MOV, WebM. Anything else is other.
// The rule when a file could be read either way is to scan it: an image
// brand anywhere in an ISO BMFF brand list makes it an image, so a crafted
// "video" can't carry a HEIF past the matcher. Never logs.
export type Sniffed =
  | { kind: "image"; mime: string }
  | { kind: "video"; mime: string }
  | { kind: "other"; reason: "empty_object" | "not_image_or_video" };

const OTHER: Sniffed = { kind: "other", reason: "not_image_or_video" };

/// ISO BMFF brands of still images and image sequences (HEIF, AVIF).
const IMAGE_BRANDS: Record<string, string> = {
  heic: "image/heic",
  heix: "image/heic",
  heim: "image/heic",
  heis: "image/heic",
  hevc: "image/heic",
  hevx: "image/heic",
  mif1: "image/heif",
  mif2: "image/heif",
  msf1: "image/heif",
  heif: "image/heif",
  avif: "image/avif",
  avis: "image/avif",
};

/// ISO BMFF major brands of audio-only files (an .m4a voice note).
const AUDIO_BRANDS = new Set(["M4A ", "M4B ", "M4P ", "F4A ", "F4B "]);

/// QuickTime files written without an ftyp box start with one of these.
const QUICKTIME_ATOMS = new Set(["moov", "mdat", "wide", "free", "skip", "pnot"]);

/// The BMP info-header sizes (BITMAPCOREHEADER .. BITMAPV5HEADER).
const BMP_DIB_SIZES = new Set([12, 16, 40, 52, 56, 64, 108, 124]);

function ascii(b: Uint8Array, start: number, length: number): string {
  if (b.length < start + length) return "";
  return String.fromCharCode(...b.subarray(start, start + length));
}

function startsWith(b: Uint8Array, signature: number[]): boolean {
  return b.length >= signature.length && signature.every((x, i) => b[i] === x);
}

function u32be(b: Uint8Array, at: number): number {
  return ((b[at] << 24) >>> 0) + (b[at + 1] << 16) + (b[at + 2] << 8) + b[at + 3];
}

function u32le(b: Uint8Array, at: number): number {
  return b[at] + (b[at + 1] << 8) + (b[at + 2] << 16) + ((b[at + 3] << 24) >>> 0);
}

/// Where the ftyp box's fields start and where the box ends (within the
/// bytes we have, and 4 KiB). Size 0 runs to the end of the file; size 1
/// is a 64-bit size after the type, so the fields start 8 bytes later
/// (B6 M-4).
function ftypBounds(b: Uint8Array): { fields: number; end: number } {
  const size = u32be(b, 0);
  const cap = Math.min(b.length, 4096);
  if (size === 0) return { fields: 8, end: cap };
  if (size === 1) {
    if (b.length < 16) return { fields: 16, end: 0 };
    const high = u32be(b, 8);
    const low = u32be(b, 12);
    return { fields: 16, end: high > 0 ? cap : Math.min(cap, low) };
  }
  return { fields: 8, end: Math.min(cap, Math.max(size, 12)) };
}

function isoBmff(b: Uint8Array): Sniffed | null {
  const box = ascii(b, 4, 4);
  if (box === "ftyp") {
    const { fields, end } = ftypBounds(b);
    if (b.length < fields + 4 || end < fields + 4) return OTHER;
    const major = ascii(b, fields, 4);
    // The brand list (after the minor version) ends with the box.
    const brands = [major];
    for (let at = fields + 8; at + 4 <= end; at += 4) brands.push(ascii(b, at, 4));
    const image = brands.find((brand) => brand in IMAGE_BRANDS);
    if (image) return { kind: "image", mime: IMAGE_BRANDS[image] };
    if (AUDIO_BRANDS.has(major)) return OTHER;
    return { kind: "video", mime: major === "qt  " ? "video/quicktime" : "video/mp4" };
  }
  if (QUICKTIME_ATOMS.has(box)) return { kind: "video", mime: "video/quicktime" };
  return null;
}

export function sniffMedia(b: Uint8Array): Sniffed {
  if (b.length === 0) return { kind: "other", reason: "empty_object" };
  if (startsWith(b, [0xff, 0xd8, 0xff])) return { kind: "image", mime: "image/jpeg" };
  if (startsWith(b, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return { kind: "image", mime: "image/png" };
  const head6 = ascii(b, 0, 6);
  if (head6 === "GIF87a" || head6 === "GIF89a") return { kind: "image", mime: "image/gif" };
  if (ascii(b, 0, 4) === "RIFF" && ascii(b, 8, 4) === "WEBP") return { kind: "image", mime: "image/webp" };
  if (ascii(b, 0, 2) === "BM" && b.length >= 18 && BMP_DIB_SIZES.has(u32le(b, 14))) {
    return { kind: "image", mime: "image/bmp" };
  }
  if (startsWith(b, [0x49, 0x49, 0x2a, 0x00]) || startsWith(b, [0x4d, 0x4d, 0x00, 0x2a])) {
    return { kind: "image", mime: "image/tiff" };
  }
  const bmff = isoBmff(b);
  if (bmff) return bmff;
  // After ISO BMFF: a 256-byte box also starts 00 00 01 00.
  // ICO (type 1) and CUR (type 2): reserved 0, the type, at least one image.
  if (b.length >= 6 && b[0] === 0 && b[1] === 0 && (b[2] === 1 || b[2] === 2) && b[3] === 0 && b[4] + (b[5] << 8) >= 1) {
    return { kind: "image", mime: "image/x-icon" };
  }
  if (startsWith(b, [0x1a, 0x45, 0xdf, 0xa3])) return { kind: "video", mime: "video/webm" };
  return OTHER;
}
