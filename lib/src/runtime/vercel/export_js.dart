import '../../core/server.dart';
import '../../esm/fetch_entry.dart' as entry;
import 'fetch_js.dart';

void defineFetchExport(Server server, {String name = '__osrv_fetch__'}) {
  entry.defineFetchExport(createVercelFetchEntry(server), name: name);
}
