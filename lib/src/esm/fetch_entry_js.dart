import '../runtime/_internal/js/fetch_entry.dart' as internal;

void defineFetchExport(
  Object fetch, {
  String name = internal.defaultFetchEntryName,
}) {
  internal.defineFetchEntry(fetch, name: name);
}
