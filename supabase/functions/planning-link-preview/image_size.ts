// Reads an image's pixel size from its header, so the preview function
// can refuse a decompression bomb (a small file declaring a huge canvas)
// before decoding it.

export const MAX_PREVIEW_PIXELS = 40_000_000;

export interface Dimensions {
  width: number;
  height: number;
}

const be16 = (b: Uint8Array, i: number) => (b[i] << 8) | b[i + 1];
const be32 = (b: Uint8Array, i: number) => ((b[i] << 24) >>> 0) + (b[i + 1] << 16) + (b[i + 2] << 8) + b[i + 3];
const le16 = (b: Uint8Array, i: number) => b[i] | (b[i + 1] << 8);
const le24 = (b: Uint8Array, i: number) => b[i] | (b[i + 1] << 8) | (b[i + 2] << 16);
const ascii = (b: Uint8Array, i: number, s: string) =>
  b.length >= i + s.length && [...s].every((c, k) => b[i + k] === c.charCodeAt(0));

/// Null when the format is unknown or the header is cut short.
export function imageDimensions(b: Uint8Array): Dimensions | null {
  if (b.length >= 24 && b[0] === 0x89 && ascii(b, 1, "PNG") && ascii(b, 12, "IHDR")) {
    return { width: be32(b, 16), height: be32(b, 20) };
  }
  if (b.length >= 10 && ascii(b, 0, "GIF8")) {
    return { width: le16(b, 6), height: le16(b, 8) };
  }
  if (b.length >= 4 && b[0] === 0xff && b[1] === 0xd8) {
    // Walk the segments to the first start-of-frame marker.
    let i = 2;
    while (i + 9 <= b.length) {
      if (b[i] !== 0xff) return null;
      const marker = b[i + 1];
      if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
        return { width: be16(b, i + 7), height: be16(b, i + 5) };
      }
      i += 2 + be16(b, i + 2);
    }
    return null;
  }
  if (b.length >= 30 && ascii(b, 0, "RIFF") && ascii(b, 8, "WEBP")) {
    if (ascii(b, 12, "VP8X")) return { width: le24(b, 24) + 1, height: le24(b, 27) + 1 };
    if (ascii(b, 12, "VP8 ")) return { width: le16(b, 26) & 0x3fff, height: le16(b, 28) & 0x3fff };
    if (ascii(b, 12, "VP8L") && b.length >= 25) {
      const bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
      return { width: (bits & 0x3fff) + 1, height: ((bits >>> 14) & 0x3fff) + 1 };
    }
  }
  return null;
}
