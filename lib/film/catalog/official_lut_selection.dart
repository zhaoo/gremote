// Route selections carry immutable cache identities, never paths or URLs.
final _officialSelection = RegExp(
    r'^official:([1-9][0-9]{0,9}):(default|ei120|ei64|ei250):[a-f0-9]{64}$');

String? officialLutSelection(String? id) {
  if (id == null) return null;
  final match = _officialSelection.firstMatch(id);
  return match != null &&
          match.end == id.length &&
          int.parse(match[1]!) <= 0xffffffff
      ? id
      : null;
}
