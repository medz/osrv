globalThis.self ??= globalThis;
import "./index.dart.js";

const handler = globalThis.__osrv_fetch__;

if (typeof handler !== "function") {
  throw new Error(
    "Missing '__osrv_fetch__' export. Ensure defineFetchExport(...) ran in the compiled Dart entry.",
  );
}

export default handler;
