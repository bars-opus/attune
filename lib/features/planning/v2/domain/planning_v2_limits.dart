/// Mirror of the server's `planning_limits()` (spec §3.11). A test parses
/// the migration literal and asserts equality, so neither side drifts.
class PlanningV2Limits {
  PlanningV2Limits._();

  static const categories = 50;
  static const blocksPerEntry = 200;
  static const itemsPerBlock = 500;
  static const payloadBytes = 16384;
  static const tableColumns = 12;
  static const tableRows = 50;
  static const photosPerBlock = 10;
  static const imageBytes = 10485760;
  static const textPlainChars = 10000;
  static const entriesPageDefault = 30;
  static const entriesPageMax = 100;
  static const titleChars = 120;
  static const categoryNameChars = 40;
  static const itemTextChars = 500;
  static const sectionChars = 40;

  static const Map<String, int> all = {
    'categories': categories,
    'blocks_per_entry': blocksPerEntry,
    'items_per_block': itemsPerBlock,
    'payload_bytes': payloadBytes,
    'table_columns': tableColumns,
    'table_rows': tableRows,
    'photos_per_block': photosPerBlock,
    'image_bytes': imageBytes,
    'text_plain_chars': textPlainChars,
    'entries_page_default': entriesPageDefault,
    'entries_page_max': entriesPageMax,
    'title_chars': titleChars,
    'category_name_chars': categoryNameChars,
    'item_text_chars': itemTextChars,
    'section_chars': sectionChars,
  };
}
