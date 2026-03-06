import '../../core/extension.dart';
import 'functions.dart';

final class VercelRuntimeExtension<Request extends Object?>
    implements RuntimeExtension {
  const VercelRuntimeExtension({
    this.functions,
    this.request,
  });

  final VercelFunctions? functions;
  final Request? request;
}
