import 'dart:io';

/// The body of the NEWEST `CREATE OR REPLACE FUNCTION public.<name>()` across
/// all migrations (a later migration may redefine a function, e.g.
/// 20261012200600 adds the notepad icon and the pin limit).
String newestSqlFunctionBody(String name) {
  final files = Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.sql'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  String? body;
  final re = RegExp('CREATE OR REPLACE FUNCTION public\\.$name\\(\\)[\\s\\S]*?\\\$\\\$([\\s\\S]*?)\\\$\\\$');
  for (final f in files) {
    for (final m in re.allMatches(f.readAsStringSync())) {
      body = m.group(1);
    }
  }
  if (body == null) throw StateError('no definition of $name');
  return body;
}
