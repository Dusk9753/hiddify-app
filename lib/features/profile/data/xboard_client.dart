import 'package:dio/dio.dart';
import 'package:hiddify/core/http_client/dio_http_client.dart';

abstract interface class XBoardTransport {
  Future<Response<dynamic>> get(String url, {required Map<String, String> headers});
  Future<Response<dynamic>> post(String url, {required Object data});
}

class DioXBoardTransport implements XBoardTransport {
  DioXBoardTransport(this._httpClient);

  final DioHttpClient _httpClient;

  @override
  Future<Response<dynamic>> get(String url, {required Map<String, String> headers}) =>
      _httpClient.get<dynamic>(url, headers: headers);

  @override
  Future<Response<dynamic>> post(String url, {required Object data}) => _httpClient.post<dynamic>(url, data: data);
}

class XBoardException implements Exception {
  const XBoardException(this.message);

  final String message;
}

class XBoardClient {
  XBoardClient({required XBoardTransport transport}) : _transport = transport;

  final XBoardTransport _transport;

  Future<String> fetchSubscribeUrl({required String baseUrl, required String email, required String password}) async {
    final apiBaseUrl = _normalizeApiBaseUrl(baseUrl);
    try {
      final loginResponse = await _transport.post(
        '$apiBaseUrl/passport/auth/login',
        data: {'email': email, 'password': password},
      );
      final authData = _requiredString(loginResponse.data, ['data', 'auth_data']);
      if (!authData.startsWith('Bearer ')) {
        throw const XBoardException('XBoard returned an invalid login session.');
      }

      final subscriptionResponse = await _transport.get(
        '$apiBaseUrl/user/getSubscribe',
        headers: {'Authorization': authData, 'Accept': 'application/json'},
      );
      final subscriptionUrl = _requiredString(subscriptionResponse.data, ['data', 'subscribe_url']);
      final subscriptionUri = Uri.tryParse(subscriptionUrl);
      if (subscriptionUri == null || !subscriptionUri.hasScheme || !subscriptionUri.hasAuthority) {
        throw const XBoardException('XBoard returned an invalid subscription address.');
      }
      return subscriptionUrl;
    } on XBoardException {
      rethrow;
    } on DioException catch (error) {
      throw XBoardException(_networkMessage(error));
    } catch (_) {
      throw const XBoardException('Unable to sign in to XBoard. Check the address and account details.');
    }
  }

  static String _normalizeApiBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme || !uri.hasAuthority || (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const XBoardException('Enter a valid XBoard address starting with http:// or https://.');
    }

    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    final apiPath = path.endsWith('/api/v1') ? path : '$path/api/v1';
    return uri.replace(path: apiPath).toString().replaceFirst(RegExp(r'/$'), '');
  }

  static String _requiredString(dynamic response, List<String> path) {
    dynamic value = response;
    for (final key in path) {
      if (value is! Map) {
        throw const XBoardException('XBoard returned an unexpected response.');
      }
      value = value[key];
    }
    if (value is! String || value.trim().isEmpty) {
      throw const XBoardException('XBoard returned an unexpected response.');
    }
    return value.trim();
  }

  static String _networkMessage(DioException error) => switch (error.response?.statusCode) {
    401 || 403 => 'XBoard rejected the sign-in. Check the email and password.',
    _ => 'Unable to reach XBoard. Check the address and try again.',
  };
}
