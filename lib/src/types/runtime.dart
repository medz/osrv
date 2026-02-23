enum RuntimeKind {
  io,
  node,
  bun,
  deno,
  cloudflare,
  vercel,
  netlify,
  js,
  unknown,
}

final class Runtime {
  const Runtime({required this.name, required this.kind});

  final String name;
  final RuntimeKind kind;

  bool get isJs => kind != RuntimeKind.io && kind != RuntimeKind.unknown;
  bool get isEdge => switch (kind) {
    RuntimeKind.cloudflare || RuntimeKind.vercel || RuntimeKind.netlify => true,
    _ => false,
  };
}
