/// Chinese presentation labels. Camera keys and values stay unchanged on wire.
String shootParamLabel(String key) =>
    const {
      'av': '光圈',
      'tv': '快门',
      'sv': '感光度',
      'xv': '曝光补偿',
      'WBMode': '白平衡',
      'meteringMode': '测光',
      'focusSetting': '对焦模式',
      'focusMode': '对焦方式',
      'exposureMode': '曝光模式',
      'shootMode': '驱动模式',
      'captureMode': '拍摄类型',
      'effect': '影像效果',
      'aspectRatio': '画幅比例',
      'stillFormat': '照片格式',
      'stillSize': '照片尺寸',
      'movieSize': '视频尺寸',
      'noiseReduction': '降噪',
      'whiteBalance': '白平衡',
      'imageQuality': '画质',
      'flashMode': '闪光模式',
      'flashComp': '闪光补偿',
      'snapDistance': '快拍距离',
      'NDFilter': '减光滤镜',
      'ndFilter': '减光滤镜',
      'crop': '裁切',
      'WBColorTemp': '色温',
      'WBShift': '白平衡偏移',
    }[key] ??
    '其他参数';

String shootValueLabel(String key, String? value) {
  if (value == null) return '—';
  if (key == 'exposureMode') {
    return const {
          'M': '手动曝光',
          'P': '程序曝光',
          'AV': '光圈优先',
          'Av': '光圈优先',
          'TV': '快门优先',
          'Tv': '快门优先',
          'TAv': '快门光圈优先',
          'B': '长时间曝光',
          'BT': '长时间曝光',
          'SFP': '快拍优先',
          'AUTO': '自动曝光',
          'U1': '自定义一',
          'U2': '自定义二',
          'U3': '自定义三',
          'U4': '自定义四',
          'U5': '自定义五',
        }[value] ??
        (value == 'GR III' ? value : '相机曝光模式');
  }
  if (key == 'effect') {
    final name = value.replaceFirst(RegExp(r'^(col_|efc_)'), '');
    return const {
          'standard': '标准',
          'natural': '自然',
          'vivid': '鲜艳',
          'monotone': '黑白',
          'monochrome': '黑白',
          'softMonotone': '柔和黑白',
          'softMonochrome': '柔和黑白',
          'hardMonotone': '硬调黑白',
          'hardMonochrome': '硬调黑白',
          'highContrast': '高对比黑白',
          'hiContrast': '高对比黑白',
          'hiContrastBW': '高对比黑白',
          'positiveFilm': '正片',
          'posiFilm': '正片',
          'negativeFilm': '负片',
          'negaFilm': '负片',
          'bleachBypass': '漂白旁路',
          'retro': '复古',
          'HDRTone': '高动态色调',
          'hdrTone': '高动态色调',
          'hdr': '高动态色调',
          'custom1': '自定义一',
          'custom2': '自定义二',
        }[name] ??
        '相机效果';
  }
  final known = const {
    'auto_hi': '自动高感',
    'multiAuto': '多区域自动白平衡',
    'daylightFluorescent': '日光色荧光灯',
    'dayWhiteFluorescent': '昼白色荧光灯',
    'coolWhiteFluorescent': '冷白色荧光灯',
    'warmWhiteFluorescent': '暖白色荧光灯',
    'cte': '强化色调',
    'colorTemp1': '色温一',
    'colorTemp2': '色温二',
    'colorTemp3': '色温三',
    'manual1': '手动一',
    'manual2': '手动二',
    'manual3': '手动三',
    'custom3': '自定义三',
    'auto': '自动',
    'manual': '手动',
    'on': '开启',
    'off': '关闭',
    'enable': '启用',
    'disable': '禁用',
    'low': '低',
    'medium': '中',
    'high': '高',
    'daylight': '日光',
    'shade': '阴影',
    'cloud': '阴天',
    'cloudy': '阴天',
    'tungsten': '白炽灯',
    'incandescent': '白炽灯',
    'fluorescent': '荧光灯',
    'flash': '闪光灯',
    'ct': '色温',
    'multi': '多区',
    'center': '中央重点',
    'spot': '点测光',
    'highlight': '高光重点',
    'af': '自动对焦',
    'mf': '手动对焦',
    'snap': '快拍',
    'inf': '无穷远',
    'infinity': '无穷远',
    'multiauto': '多点自动',
    'pinpoint': '精确对焦',
    'tracking': '追踪对焦',
    'zone_select': '区域选择',
    'multiauto_center': '中央自动',
    'continuous': '连续',
    'single': '单张',
    'self2s': '自拍 2 秒',
    'self10s': '自拍 10 秒',
    'self12s': '自拍 12 秒',
    'bracket': '曝光包围',
    'dofBracket': '景深包围',
    'motionBracket': '运动包围',
    'interval': '间隔拍摄',
    'intervalComp': '间隔合成',
    'intervalMovie': '间隔视频',
    'multiExp': '多重曝光',
    'remocon': '遥控',
    'remocon3s': '遥控 3 秒',
    'jpeg': '压缩照片',
    'dng': '原始照片',
    'rawdng': '原始照片',
    'rawdng+jpeg': '原始与压缩照片',
    'raw+jpeg': '原始与压缩照片',
    'still': '照片',
    'movie': '视频',
    'none': '无',
    'strong': '强',
    'weak': '弱',
  }[value];
  if (known != null) return known;
  // Numeric camera readings and Chinese/user supplied names need no translation.
  if (!RegExp(r'[A-Za-z]').hasMatch(value)) return value;
  if (key == 'shootMode') {
    for (final entry in const {
      'continuousH': '高速连拍',
      'continuousM': '中速连拍',
      'continuousL': '低速连拍',
      'intervalComp': '间隔合成',
      'intervalMovie': '间隔视频',
      'interval': '间隔拍摄',
      'multiExpContinuous': '多重曝光连拍',
      'multiExp': '多重曝光',
      'motionBracket': '运动包围',
      'dofBracket': '景深包围',
      'bracket': '曝光包围',
      'mirrorUp': '反光板预升',
      'starstream': '星轨',
    }.entries) {
      if (value.startsWith(entry.key)) {
        final suffix = value.substring(entry.key.length);
        return '${entry.value}${suffix.isEmpty ? '' : ' · ${shootValueLabel(key, suffix[0].toLowerCase() + suffix.substring(1))}'}';
      }
    }
  }
  return '相机选项';
}

String shootReasonLabel(String reason) =>
    const {
      'user': '已暂停',
      'background': '应用进入后台',
      'disconnected': '相机已断开',
      'hot': '相机温度过高',
      'failure': '拍摄失败',
    }[reason] ??
    (RegExp(r'[A-Za-z]').hasMatch(reason) ? '拍摄已暂停' : reason);
