final class BunHostObject {
  const BunHostObject();
}

final class BunGlobal {
  const BunGlobal({
    this.version,
    this.serve,
  });

  final String? version;
  final Object? serve;
}

BunHostObject? get globalThis => null;

BunGlobal? get bunGlobal => null;

String? bunVersion(BunGlobal bun) => bun.version;

bool bunHasServe(BunGlobal bun) => bun.serve != null;
