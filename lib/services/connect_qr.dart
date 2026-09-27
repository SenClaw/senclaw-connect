/// Pairing QR shared with the desktop app and the web console.
///
/// Those clients mint `senclaw://connect?hub&cid&key&token`. Codes printed
/// before the repo split used `semaclaw://`; scanning still accepts that so a
/// code already on screen keeps working. This app mints the `senclaw` scheme.
const connectQrScheme = 'senclaw';

bool isConnectQr(String code) {
  final uri = Uri.tryParse(code);
  if (uri == null || uri.host != 'connect') return false;
  return uri.scheme == 'senclaw' || uri.scheme == 'semaclaw';
}

Uri connectQrUri({
  required String hub,
  required String cid,
  required String key,
  String? token,
}) {
  return Uri(
    scheme: connectQrScheme,
    host: 'connect',
    queryParameters: {
      'hub': hub,
      'cid': cid,
      'key': key,
      'token': ?token,
    },
  );
}
