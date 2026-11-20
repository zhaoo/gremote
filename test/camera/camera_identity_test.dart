import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/model/camera_identity.dart';

void main() {
  test('HDF model identities keep the same family capability boundary', () {
    for (final model in [
      'RICOH GR III HDF',
      'RICOH GR IIIx HDF',
      'RICOH GR IV HDF'
    ]) {
      final identity = CameraIdentity(model: model, firmware: '1.00');
      expect(identity.isSupportedModel, isTrue);
      expect(identity.supportsM10v, !model.startsWith('RICOH GR IV'));
    }
  });
  test('supported families are exact and M10V stays on III / IIIx', () {
    for (final model in [
      'RICOH GR III',
      'RICOH GR IIIx',
      'RICOH GR IV',
      'RICOH GR IV Monochrome'
    ]) {
      final identity = CameraIdentity(model: model, firmware: '1.00');
      expect(identity.isSupportedModel, isTrue);
      expect(identity.supportsM10v,
          model == 'RICOH GR III' || model == 'RICOH GR IIIx');
    }
    for (final model in ['', 'GR III', 'RICOH GR IV fake', 'RICOH GR II']) {
      expect(
          CameraIdentity(model: model, firmware: '').isSupportedModel, isFalse);
    }
    expect(
        const CameraIdentity(model: 'RICOH GR IV', firmware: '2.10')
            .isVerifiedFirmware,
        isFalse);
  });
}
