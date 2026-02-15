import 'dart:io';

Future<void> main() async {
  final dist = Directory('dist');
  if (!dist.existsSync()) {
    dist.createSync(recursive: true);
  }

  for (final path in <String>[
    'dist/js/core',
    'dist/js/node',
    'dist/js/bun',
    'dist/js/deno',
    'dist/edge/cloudflare',
    'dist/edge/vercel',
    'dist/edge/netlify',
    'dist/bin',
  ]) {
    Directory(path).createSync(recursive: true);
  }

  await _run('dart', <String>[
    'compile',
    'js',
    'tool/entrypoints/osrv_js_entry.dart',
    '-o',
    'dist/js/core/osrv_core.js',
  ]);

  final executableName = Platform.isWindows ? 'osrv.exe' : 'osrv';
  await _run('dart', <String>[
    'compile',
    'exe',
    'bin/osrv.dart',
    '-o',
    'dist/bin/$executableName',
  ]);

  File('dist/js/node/index.mjs').writeAsStringSync(_nodeWrapper);
  File('dist/js/bun/index.mjs').writeAsStringSync(_bunWrapper);
  File('dist/js/deno/index.mjs').writeAsStringSync(_denoWrapper);

  File('dist/edge/cloudflare/index.mjs').writeAsStringSync(_cloudflareWrapper);
  File('dist/edge/vercel/index.mjs').writeAsStringSync(_vercelWrapper);
  File('dist/edge/netlify/index.mjs').writeAsStringSync(_netlifyWrapper);

  stdout.writeln('Build complete. Artifacts are under dist/.');
}

Future<void> _run(String executable, List<String> arguments) async {
  stdout.writeln('\$ $executable ${arguments.join(' ')}');
  final process = await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.inheritStdio,
  );
  final code = await process.exitCode;
  if (code != 0) {
    throw ProcessException(executable, arguments, 'Command failed', code);
  }
}

const String _nodeWrapper = '''
import '../core/osrv_core.js';

export function serve(options = {}) {
  throw new Error(
    'osrv node adapter scaffold generated. Connect runtime bridge from Dart core to Node HTTP APIs.',
  );
}
''';

const String _bunWrapper = '''
import '../core/osrv_core.js';

export function serve(options = {}) {
  throw new Error(
    'osrv bun adapter scaffold generated. Connect runtime bridge from Dart core to Bun.serve APIs.',
  );
}
''';

const String _denoWrapper = '''
import '../core/osrv_core.js';

export function serve(options = {}) {
  throw new Error(
    'osrv deno adapter scaffold generated. Connect runtime bridge from Dart core to Deno.serve APIs.',
  );
}
''';

const String _cloudflareWrapper = '''
import '../../js/core/osrv_core.js';

export default {
  async fetch(request, env, ctx) {
    if (typeof globalThis.__osrv_main__ === 'function') {
      return globalThis.__osrv_main__(request, { env, ctx, provider: 'cloudflare' });
    }

    return new Response('osrv Cloudflare adapter scaffold generated.', { status: 501 });
  },
};
''';

const String _vercelWrapper = '''
import '../../js/core/osrv_core.js';

export default async function handler(request, context) {
  if (typeof globalThis.__osrv_main__ === 'function') {
    return globalThis.__osrv_main__(request, {
      env: context?.env ?? {},
      ctx: context,
      provider: 'vercel',
    });
  }

  return new Response('osrv Vercel adapter scaffold generated.', { status: 501 });
}
''';

const String _netlifyWrapper = '''
import '../../js/core/osrv_core.js';

export default async (request, context) => {
  if (typeof globalThis.__osrv_main__ === 'function') {
    return globalThis.__osrv_main__(request, {
      env: context?.env ?? {},
      ctx: context,
      provider: 'netlify',
    });
  }

  return new Response('osrv Netlify adapter scaffold generated.', { status: 501 });
};
''';
