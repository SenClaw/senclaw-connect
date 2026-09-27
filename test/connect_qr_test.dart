import 'package:flutter_test/flutter_test.dart';
import 'package:senclaw_connect/services/connect_qr.dart';

void main() {
  test('mints the senclaw scheme desktop and web already emit', () {
    final uri = connectQrUri(
      hub: 'https://hub.example',
      cid: 'ch-1',
      key: 'aabb',
      token: 'tok',
    );
    expect(uri.scheme, 'senclaw');
    expect(uri.host, 'connect');
    expect(uri.queryParameters['hub'], 'https://hub.example');
    expect(uri.queryParameters['cid'], 'ch-1');
    expect(isConnectQr(uri.toString()), isTrue);
  });

  test('still accepts a QR minted with the old semaclaw scheme', () {
    expect(
      isConnectQr('semaclaw://connect?hub=https://h&cid=c&key=k&token=t'),
      isTrue,
    );
  });

  test('rejects a code that is not a connect QR', () {
    expect(isConnectQr('https://example.com'), isFalse);
    expect(isConnectQr('senclaw://open'), isFalse);
    expect(isConnectQr('not a uri'), isFalse);
  });
}
