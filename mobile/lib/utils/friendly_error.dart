import 'package:dio/dio.dart';

/// Convierte una excepción en un mensaje legible para mostrar al usuario.
///
/// Nunca devuelve el texto crudo de la excepción; en su lugar, genera
/// un mensaje descriptivo y natural según el tipo de error.
String friendlyError(Object error, {String? contexto}) {
  final prefijo = contexto != null ? '$contexto. ' : '';

  if (error is DioException) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
        return '${prefijo}El servidor tarda demasiado en responder. Comprueba tu conexión e inténtalo de nuevo.';
      case DioExceptionType.receiveTimeout:
        return '${prefijo}La respuesta del servidor se ha agotado. Inténtalo de nuevo en unos minutos.';
      case DioExceptionType.connectionError:
        return '${prefijo}No se pudo conectar con el servidor. Comprueba tu conexión a internet.';
      case DioExceptionType.badResponse:
        final code = error.response?.statusCode;
        final data = error.response?.data;
        // Si el backend envía un mensaje, usarlo.
        if (data is Map && data['message'] is String) {
          return '$prefijo${data['message']}';
        }
        if (code == 401) {
          return '${prefijo}Tu sesión ha caducado. Vuelve a iniciar sesión.';
        }
        if (code == 403) {
          return '${prefijo}No tienes permiso para realizar esta acción.';
        }
        if (code == 404) {
          return '${prefijo}No se encontró el recurso solicitado.';
        }
        if (code == 422) {
          return '${prefijo}Algunos datos no son válidos. Revísalos e inténtalo de nuevo.';
        }
        if (code != null && code >= 500) {
          return '${prefijo}Hay un problema en el servidor. Inténtalo de nuevo más tarde.';
        }
        return '${prefijo}Error inesperado del servidor (código $code).';
      case DioExceptionType.cancel:
        return '${prefijo}La operación fue cancelada.';
      case DioExceptionType.badCertificate:
        return '${prefijo}Hay un problema de seguridad con la conexión. Contacta con soporte.';
      case DioExceptionType.unknown:
        final msg = error.error?.toString() ?? '';
        if (msg.contains('SocketException') ||
            msg.contains('connection abort') ||
            msg.contains('Connection reset') ||
            msg.contains('HttpException')) {
          return '${prefijo}Se perdió la conexión con el servidor. Comprueba tu conexión e inténtalo de nuevo.';
        }
        return '${prefijo}Ha ocurrido un error de red. Inténtalo de nuevo.';
    }
  }

  if (error is FormatException) {
    return '${prefijo}Los datos recibidos no tienen el formato esperado.';
  }

  if (error is StateError) {
    return '$prefijo${error.message}';
  }

  return '${prefijo}Ha ocurrido un error inesperado. Inténtalo de nuevo.';
}
