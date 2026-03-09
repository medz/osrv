import '../../core/server.dart';
import '../../esm/fetch_entry.dart' as entry;

void defineFetchExport(Server server, {String name = '__osrv_fetch__'}) {
  entry.defineFetchExport(server, name: name);
}
