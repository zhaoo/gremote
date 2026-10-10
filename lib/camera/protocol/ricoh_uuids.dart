abstract final class RicohGattIds {
  static const cameraInformationService =
      '9a5ed1c5-74cc-4c50-b5b6-66a48e7ccff1';
  static const model = '35fe6272-6aa5-44d9-88e1-f09427f51a71';
  static const firmware = 'b4eb8905-7411-40a6-a367-2834c2157ea7';

  static const cameraService = '4b445988-caa0-4dd3-941d-37b4f52aca86';
  static const cameraPower = 'b58ce84c-0666-4de9-bec8-2d27b27b3211';
  static const battery = '875fc41d-4980-434c-a653-fd4a4d4410c4';
  static const operationMode = '1452335a-ec7f-4877-b8ab-0f72e18bb295';

  static const wlanService = 'f37f568f-9071-445d-a938-5441f2e82399';
  static const networkType = '9111cdd0-9f01-45c4-a2d4-e09e8fb0424d';
  static const ssid = '90638e5a-e77d-409d-b550-78f7e1ca5ab4';
  static const passphrase = '0f38279c-fe9e-461b-8596-81287e8c9a81';

  static const shootingService = '9f00f387-8345-4bbc-8b92-b87b52e3091a';
  static const operationRequest = '559644b8-e0bc-4011-929b-5cf9199851e7';
  static const captureStatus = 'b5589c08-b5fd-46f5-be7d-ab1b8c074caa';

  static const requiredBootstrapCharacteristics = {
    model,
    firmware,
    battery,
    cameraPower,
    networkType,
    ssid,
    passphrase,
  };
}
