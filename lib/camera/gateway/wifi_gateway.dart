abstract interface class WifiGateway {
  Future<void> connect({required String ssid, required String passphrase});

  Future<void> disconnect();
}
