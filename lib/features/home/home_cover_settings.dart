import '../../media/local/local_media_repository.dart';

class HomeCoverEntry {
  const HomeCoverEntry(
      {required this.id, required this.uri, this.x = 0, this.y = 0});
  final int id;
  final String uri;
  final double x, y;
  Map<String, Object> toJson() => {'id': id, 'uri': uri, 'x': x, 'y': y};
  factory HomeCoverEntry.fromJson(Map<String, dynamic> value) {
    final id = value['id'], uri = value['uri'], x = value['x'], y = value['y'];
    if (id is! int ||
        id < 0 ||
        uri is! String ||
        uri.isEmpty ||
        x is! num ||
        y is! num ||
        !x.isFinite ||
        !y.isFinite ||
        x.abs() > 1 ||
        y.abs() > 1) {
      throw const FormatException('封面记录无效');
    }
    return HomeCoverEntry(id: id, uri: uri, x: x.toDouble(), y: y.toDouble());
  }
}

class HomeCoverSettings {
  const HomeCoverSettings(
      {this.useDefault = false, this.autoplay = true, this.entries = const []});
  final bool useDefault, autoplay;
  final List<HomeCoverEntry> entries;
  Map<String, Object> toJson() => {
        'version': 1,
        'useDefault': useDefault,
        'autoplay': autoplay,
        'entries': entries.map((e) => e.toJson()).toList()
      };
  factory HomeCoverSettings.fromJson(Map<String, dynamic> v) {
    if (v['version'] != 1 ||
        v['useDefault'] is! bool ||
        v['autoplay'] is! bool ||
        v['entries'] is! List) throw const FormatException('封面配置无效');
    try {
      final entries = (v['entries'] as List)
          .map((e) =>
              HomeCoverEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      if (entries.length > 5 ||
          entries.map((e) => e.id).toSet().length != entries.length) {
        throw const FormatException('封面选择无效');
      }
      return HomeCoverSettings(
          useDefault: v['useDefault'] as bool,
          autoplay: v['autoplay'] as bool,
          entries: List.unmodifiable(entries));
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('封面配置无效');
    }
  }
}

List<LocalMediaItem> resolveCoverItems(
    HomeCoverSettings settings, List<LocalMediaItem> available) {
  if (settings.useDefault) return [];
  if (settings.entries.isEmpty) return available.take(5).toList();
  return [
    for (final entry in settings.entries)
      ...available.where((e) => e.id == entry.id && e.uri == entry.uri).take(1)
  ].take(5).toList();
}
