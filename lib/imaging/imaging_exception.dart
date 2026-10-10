enum ImagingErrorCode {
  invalidArgument(1, '参数无效'),
  io(2, '读写失败'),
  decode(3, '无法解码图片'),
  lutParse(4, 'LUT 格式不正确'),
  lutRange(5, 'LUT 数值超出范围'),
  tooLarge(6, '图片或文件过大'),
  outOfMemory(7, '内存不足'),
  cancelled(8, '已取消'),
  encode(9, '编码失败'),
  unknown(-1, '未知错误');

  const ImagingErrorCode(this.value, this.label);

  final int value;
  final String label;

  static ImagingErrorCode fromValue(int value) => values.firstWhere(
        (code) => code.value == value,
        orElse: () => unknown,
      );
}

class ImagingException implements Exception {
  const ImagingException(this.code);

  final ImagingErrorCode code;

  @override
  String toString() => 'ImagingException(${code.name}: ${code.label})';
}
