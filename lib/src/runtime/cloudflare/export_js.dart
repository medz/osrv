import '../../core/server.dart';
import '../../esm/fetch_entry.dart' as entry;
import 'worker_js.dart';

void defineFetchExport(Server server, {String name = '__osrv_fetch__'}) {
  entry.defineFetchExport(createCloudflareFetchEntry(server), name: name);
}
