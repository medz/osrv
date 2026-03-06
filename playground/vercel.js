import { geolocation, getEnv, ipAddress, waitUntil } from "@vercel/functions";
import "./vercel.dart.js";

export default {
  fetch: (request) =>
    globalThis.__osrv_vercel_fetch__(request, {
      waitUntil,
      getEnv,
      geolocation,
      ipAddress,
    }),
};
