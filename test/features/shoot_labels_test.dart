import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/features/shoot/shoot_labels.dart';

void main() {
  test('firmware high contrast and HDR effects remain distinguishable', () {
    expect(shootValueLabel('effect', 'hiContrastBW'), '高对比黑白');
    expect(shootValueLabel('effect', 'hdrTone'), '高动态色调');
  });
  test('firmware aliases are translated without changing camera values', () {
    expect(shootValueLabel('effect', 'efc_posiFilm'), '正片');
    expect(shootValueLabel('effect', 'efc_softMonochrome'), '柔和黑白');
    expect(shootValueLabel('exposureMode', 'AV'), '光圈优先');
    expect(shootValueLabel('focusSetting', 'inf'), '无穷远');
    expect(shootValueLabel('shootMode', 'intervalSelf10s'), '间隔拍摄 · 自拍 10 秒');
    expect(shootValueLabel('tv', '1/250'), '1/250');
    expect(shootValueLabel('sv', 'auto'), '自动');
    expect(shootParamLabel('noiseReduction'), '降噪');
    expect(shootReasonLabel('disconnected'), '相机已断开');
  });
}
