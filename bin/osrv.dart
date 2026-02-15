import 'dart:async';
import 'dart:io';

import 'package:args/args.dart';
import 'package:osrv/build.dart';

const String _defaultEntry = 'server.dart';
const String _defaultFallbackEntry = 'bin/server.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addCommand('serve')
    ..addCommand('build');

  parser.commands['serve']!
    ..addOption(
      'entry',
      defaultsTo: _defaultEntry,
      help: 'Dart entry file. Defaults to `server.dart`.',
    )
    ..addOption('port', help: 'Port to listen on.')
    ..addOption('hostname', help: 'Hostname to bind to.')
    ..addOption(
      'protocol',
      allowed: <String>['http', 'https'],
      help: 'Protocol preference.',
    )
    ..addFlag(
      'tls',
      defaultsTo: null,
      negatable: true,
      help: 'Enable TLS mode for the spawned server process.',
    )
    ..addOption('cert', help: 'TLS certificate path or PEM content.')
    ..addOption('key', help: 'TLS private key path or PEM content.')
    ..addOption('passphrase', help: 'TLS private key passphrase.')
    ..addFlag(
      'http2',
      defaultsTo: null,
      negatable: true,
      help: 'Request HTTP/2 mode when the runtime supports it.',
    )
    ..addFlag('silent', defaultsTo: false, help: 'Silence osrv CLI logs.');

  parser.commands['build']!
    ..addOption(
      'entry',
      defaultsTo: _defaultEntry,
      help: 'Dart entry file to compile. Defaults to `server.dart`.',
    )
    ..addOption('out-dir', defaultsTo: 'dist', help: 'Build output directory.')
    ..addFlag(
      'silent',
      defaultsTo: false,
      help: 'Silence build progress logs.',
    );

  ArgResults result;
  try {
    result = parser.parse(args);
  } on FormatException catch (error) {
    stderr.writeln('[osrv] ${error.message}');
    stderr.writeln(parser.usage);
    exitCode = 64;
    return;
  }

  final command = result.command;
  if (command == null) {
    stdout.writeln('osrv commands:');
    stdout.writeln(parser.usage);
    return;
  }

  switch (command.name) {
    case 'serve':
      await _runServe(command);
      return;
    case 'build':
      await _runBuild(command);
      return;
    default:
      stderr.writeln('[osrv] unknown command: ${command.name}');
      exitCode = 64;
      return;
  }
}

Future<void> _runServe(ArgResults command) async {
  final requestedEntry = command['entry'] as String;
  final entry = resolveEntry(
    requestedEntry,
    defaultEntry: _defaultEntry,
    fallbackEntry: _defaultFallbackEntry,
  );
  if (entry == null) {
    stderr.writeln(
      '[osrv] entry not found. looked for `$requestedEntry` '
      'and fallback `$_defaultFallbackEntry`.',
    );
    exitCode = 66;
    return;
  }

  final env = Platform.environment;

  final port =
      _firstNonEmpty(
        command['port'] as String?,
        env['PORT'],
        env['OSRV_PORT'],
      ) ??
      '3000';

  final hostname =
      _firstNonEmpty(
        command['hostname'] as String?,
        env['HOSTNAME'],
        env['OSRV_HOSTNAME'],
      ) ??
      '0.0.0.0';

  final protocol = _firstNonEmpty(
    command['protocol'] as String?,
    env['OSRV_PROTOCOL'],
  );
  final tlsFlag = command['tls'] as bool?;
  final certFromArgs = command['cert'] as String?;
  final keyFromArgs = command['key'] as String?;
  final passphraseFromArgs = command['passphrase'] as String?;
  final http2Flag = command['http2'] as bool?;

  final envTls = _parseBoolish(_firstNonEmpty(env['OSRV_TLS'], env['TLS']));
  final envHttp2 = _parseBoolish(env['OSRV_HTTP2']);

  var cert = _firstNonEmpty(
    certFromArgs,
    env['OSRV_TLS_CERT'],
    env['TLS_CERT'],
  );
  var key = _firstNonEmpty(keyFromArgs, env['OSRV_TLS_KEY'], env['TLS_KEY']);
  var passphrase = _firstNonEmpty(
    passphraseFromArgs,
    env['OSRV_TLS_PASSPHRASE'],
    env['TLS_PASSPHRASE'],
  );

  final tlsEnabled = tlsFlag ?? envTls ?? (cert != null && key != null);
  if (!tlsEnabled) {
    cert = null;
    key = null;
    passphrase = null;
  }

  final effectiveProtocol = protocol ?? (tlsEnabled ? 'https' : 'http');
  final http2Enabled = http2Flag ?? envHttp2 ?? false;

  final spawnedEnv = <String, String>{
    ...env,
    'PORT': port,
    'HOSTNAME': hostname,
    'OSRV_PORT': port,
    'OSRV_HOSTNAME': hostname,
    'OSRV_PROTOCOL': effectiveProtocol,
    'OSRV_TLS': tlsEnabled ? 'true' : 'false',
    'OSRV_HTTP2': http2Enabled ? 'true' : 'false',
    'OSRV_NODE_HTTP2': http2Enabled ? 'true' : 'false',
    'OSRV_BUN_HTTP2': http2Enabled ? 'true' : 'false',
    'OSRV_DENO_HTTP2': http2Enabled ? 'true' : 'false',
    'OSRV_TLS_CERT': cert ?? '',
    'OSRV_TLS_KEY': key ?? '',
    'OSRV_TLS_PASSPHRASE': passphrase ?? '',
    'TLS_CERT': cert ?? '',
    'TLS_KEY': key ?? '',
    'TLS_PASSPHRASE': passphrase ?? '',
  };

  if (!(command['silent'] as bool)) {
    stdout.writeln(
      '[osrv] serving `$entry` with '
      'PORT=$port HOSTNAME=$hostname PROTOCOL=$effectiveProtocol '
      'TLS=${tlsEnabled ? 'on' : 'off'} '
      'CERT=${cert != null ? 'set' : 'unset'} '
      'KEY=${key != null ? 'set' : 'unset'} '
      'HTTP2=${http2Enabled ? 'on' : 'off'}',
    );
  }

  final child = await Process.start(
    'dart',
    <String>['run', entry],
    mode: ProcessStartMode.inheritStdio,
    environment: spawnedEnv,
  );

  final signalSubscriptions = <StreamSubscription<ProcessSignal>>[];

  void watchSignal(ProcessSignal signal) {
    try {
      signalSubscriptions.add(
        signal.watch().listen((_) {
          if (!child.kill(signal)) {
            child.kill();
          }
        }),
      );
    } on UnsupportedError {
      // Some signals are not supported on all platforms.
    }
  }

  watchSignal(ProcessSignal.sigint);
  watchSignal(ProcessSignal.sigterm);
  if (!Platform.isWindows) {
    watchSignal(ProcessSignal.sighup);
  }

  final childExitCode = await child.exitCode;
  for (final subscription in signalSubscriptions) {
    await subscription.cancel();
  }
  exitCode = childExitCode;
}

Future<void> _runBuild(ArgResults command) async {
  final requestedEntry = command['entry'] as String;
  final outDir = command['out-dir'] as String;
  final silent = command['silent'] as bool;

  try {
    await build(
      BuildOptions(
        entry: requestedEntry,
        outDir: outDir,
        silent: silent,
        defaultEntry: _defaultEntry,
        fallbackEntry: _defaultFallbackEntry,
      ),
      logger: silent ? null : stdout.writeln,
    );
  } on ArgumentError {
    stderr.writeln(
      '[osrv] entry not found. looked for `$requestedEntry` '
      'and fallback `$_defaultFallbackEntry`.',
    );
    exitCode = 66;
    return;
  }
}

String? _firstNonEmpty(String? first, String? second, [String? third]) {
  for (final value in <String?>[first, second, third]) {
    if (value != null && value.isNotEmpty) {
      return value;
    }
  }

  return null;
}

bool? _parseBoolish(String? value) {
  if (value == null) {
    return null;
  }

  final normalized = value.trim().toLowerCase();
  if (normalized.isEmpty) {
    return null;
  }
  if (normalized == '1' ||
      normalized == 'true' ||
      normalized == 'yes' ||
      normalized == 'on') {
    return true;
  }
  if (normalized == '0' ||
      normalized == 'false' ||
      normalized == 'no' ||
      normalized == 'off') {
    return false;
  }

  return null;
}
