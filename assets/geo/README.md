# Geographic assets

`land_50m_merc.bin` — world land outline for the home-screen distance widget's
region map. Made with Natural Earth (1:50m land), public domain:
https://www.naturalearthdata.com/about/terms-of-use/

Built by `dart run tool/build_land_outline.dart <ne_50m_land.geojson> assets/geo/land_50m_merc.bin`.
Format: "LND1", uint32 ring count, then per ring uint32 n and n × (uint16 x,
uint16 y) Web Mercator world units × 65535 (latitude clamped to ±85).
Little-endian.
