import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hiddify/features/profile/data/xboard_client.dart';

void main() {
  group('XBoardClient', () {
    test('logs in and returns the server-issued subscription URL', () async {
      final transport = _FakeTransport();
      final client = XBoardClient(transport: transport);

      final url = await client.fetchSubscribeUrl(
        baseUrl: 'https://panel.example.com/',
        email: 'user@example.com',
        password: 'secret',
      );

      expect(url, 'https://panel.example.com/api/v1/client/subscribe?token=issued-token');
      expect(transport.loginUrl, 'https://panel.example.com/api/v1/passport/auth/login');
      expect(transport.subscribeUrl, 'https://panel.example.com/api/v1/user/getSubscribe');
      expect(transport.subscribeHeaders, {'Authorization': 'Bearer session-token', 'Accept': 'application/json'});
    });

    test('rejects a malformed panel address before sending credentials', () async {
      final transport = _FakeTransport();
      final client = XBoardClient(transport: transport);

      await expectLater(
        client.fetchSubscribeUrl(baseUrl: 'panel.example.com', email: 'user@example.com', password: 'secret'),
        throwsA(isA<XBoardException>()),
      );
      expect(transport.loginUrl, isNull);
    });
  });
}

class _FakeTransport implements XBoardTransport {
  String? loginUrl;
  String? subscribeUrl;
  Map<String, String>? subscribeHeaders;

  @override
  Future<Response<dynamic>> get(String url, {required Map<String, String> headers}) async {
    subscribeUrl = url;
    subscribeHeaders = headers;
    return Response(
      requestOptions: RequestOptions(path: url),
      data: {
        'data': {'subscribe_url': 'https://panel.example.com/api/v1/client/subscribe?token=issued-token'},
      },
    );
  }

  @override
  Future<Response<dynamic>> post(String url, {required Object data}) async {
    loginUrl = url;
    return Response(
      requestOptions: RequestOptions(path: url),
      data: {
        'data': {'auth_data': 'Bearer session-token'},
      },
    );
  }
}
