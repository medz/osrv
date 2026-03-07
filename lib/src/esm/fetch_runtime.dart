/// Supported JavaScript entrypoint targets.
enum FetchEntryRuntime {
  /// Emits a Cloudflare Worker fetch handler.
  cloudflare,

  /// Emits a Vercel fetch handler.
  vercel,
}
