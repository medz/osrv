import 'dart:js_interop';
import 'dart:js_interop_unsafe';

void publishCloudflareWorker(Object worker) {
  globalContext.setProperty(
    '__osrvCloudflareWorker'.toJS,
    worker as JSObject,
  );
}
