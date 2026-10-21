import '../model/film_roll.dart';

class ContactSheetPage {
  ContactSheetPage(this.index, List<RollItem> items)
      : items = List.unmodifiable(items);
  final int index;
  final List<RollItem> items;
  static const width = 1440;
  int get rows => (items.length + 3) ~/ 4;
  int get height => 240 + rows * 268;
}

class ContactSheetLayout {
  static List<ContactSheetPage> pages(List<RollItem> items,
      {int pageSize = 24}) {
    if (pageSize < 1 || pageSize > 24) throw ArgumentError.value(pageSize);
    return [
      for (var start = 0; start < items.length; start += pageSize)
        ContactSheetPage(start ~/ pageSize,
            items.sublist(start, (start + pageSize).clamp(0, items.length)))
    ];
  }
}
