@JS()
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

const defaultFetchEntryName = '__osrv_fetch__';

void defineFetchEntry(Object fetch, {String name = defaultFetchEntryName}) {
  if (name.trim().isEmpty) {
    throw ArgumentError.value(
      name,
      'name',
      'Fetch entry export name must not be empty.',
    );
  }

  globalContext.setProperty(name.toJS, fetch as JSAny);
}
