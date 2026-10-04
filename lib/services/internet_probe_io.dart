import 'dart:async';
import 'dart:io';

Future<bool> hasInternetAccess() async {
  try {
    final result = await InternetAddress.lookup(
      'firestore.googleapis.com',
    ).timeout(const Duration(seconds: 5));
    return result.isNotEmpty && result.any((address) => address.rawAddress.isNotEmpty);
  } on SocketException {
    return false;
  } on TimeoutException {
    return false;
  }
}
