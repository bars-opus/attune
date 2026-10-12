import { assertEquals } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { imageDimensions, MAX_PREVIEW_PIXELS } from "./image_size.ts";

const u32 = (n: number) => [(n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255];

Deno.test("PNG, GIF, JPEG and WebP sizes are read from the header without decoding", () => {
  const png = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 0x49, 0x48, 0x44, 0x52, ...u32(20000), ...u32(20000)]);
  assertEquals(imageDimensions(png), { width: 20000, height: 20000 });

  const gif = new Uint8Array([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x40, 0x01, 0xf0, 0x00]);
  assertEquals(imageDimensions(gif), { width: 320, height: 240 });

  // SOI, an APP0 segment, then SOF0 with height 600, width 800.
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x04, 0x00, 0x00, 0xff, 0xc0, 0x00, 0x11, 0x08, 0x02, 0x58, 0x03, 0x20]);
  assertEquals(imageDimensions(jpeg), { width: 800, height: 600 });

  // VP8X: 24-bit (width-1) and (height-1) at bytes 24..29.
  const webp = new Uint8Array(30);
  webp.set([0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50, 0x56, 0x50, 0x38, 0x58]);
  webp.set([0x1f, 0x03, 0x00, 0x57, 0x02, 0x00], 24); // 800 x 600
  assertEquals(imageDimensions(webp), { width: 800, height: 600 });
});

Deno.test("unknown or truncated images have no size; the cap is about 40 megapixels", () => {
  assertEquals(imageDimensions(new Uint8Array([1, 2, 3])), null);
  assertEquals(imageDimensions(new Uint8Array([0xff, 0xd8, 0xff])), null);
  assertEquals(MAX_PREVIEW_PIXELS, 40_000_000);
});
