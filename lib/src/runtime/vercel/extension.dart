import '../../core/extension.dart';
import 'functions.dart';

final class VercelRuntimeExtension<
    Helpers extends Object?,
    Request extends Object?> implements RuntimeExtension {
  const VercelRuntimeExtension({
    this.functions,
    this.helpers,
    this.request,
    this.env,
    this.geolocation,
    this.ipAddress,
  });

  final VercelFunctions? functions;
  final Helpers? helpers;
  final Request? request;
  final Object? env;
  final Object? geolocation;
  final String? ipAddress;
}
