import '../../core/extension.dart';
import 'functions.dart';

/// Exposes Vercel-specific helpers through [RequestContext.extension].
final class VercelRuntimeExtension<Request extends Object?>
    implements RuntimeExtension {
  /// Creates a Vercel runtime extension snapshot.
  const VercelRuntimeExtension({this.functions, this.request});

  /// Vercel helper APIs bound to the current request when available.
  final VercelFunctions? functions;

  /// The host-native request value for the current invocation.
  final Request? request;
}
