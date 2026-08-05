import 'dart:convert';
import 'dart:typed_data';

List<String> torrentFilePaths(List<int> bytes) {
  final root = _Bencode(Uint8List.fromList(bytes)).parse();
  if (root is! Map) throw const FormatException('Not a torrent file');
  final info = root['info'];
  if (info is! Map) throw const FormatException('Missing info dict');
  final files = info['files'];
  if (files is List) {
    return files
        .map((f) => ((f as Map)['path'] as List).cast<String>().join('/'))
        .toList(growable: false);
  }
  final name = info['name'];
  if (name is! String) throw const FormatException('Missing name');
  return [name];
}

class _Bencode {
  _Bencode(this._bytes);

  final Uint8List _bytes;
  int _pos = 0;

  dynamic parse() {
    switch (_bytes[_pos]) {
      case 0x64:
        return _dict();
      case 0x6c:
        return _list();
      case 0x69:
        return _int();
      default:
        return _string();
    }
  }

  Map<String, dynamic> _dict() {
    _pos++;
    final map = <String, dynamic>{};
    while (_bytes[_pos] != 0x65) {
      final key = _string();
      map[key] = parse();
    }
    _pos++;
    return map;
  }

  List<dynamic> _list() {
    _pos++;
    final list = <dynamic>[];
    while (_bytes[_pos] != 0x65) {
      list.add(parse());
    }
    _pos++;
    return list;
  }

  int _int() {
    _pos++;
    final end = _bytes.indexOf(0x65, _pos);
    final value = int.parse(ascii.decode(_bytes.sublist(_pos, end)));
    _pos = end + 1;
    return value;
  }

  String _string() {
    final colon = _bytes.indexOf(0x3a, _pos);
    final length = int.parse(ascii.decode(_bytes.sublist(_pos, colon)));
    _pos = colon + 1 + length;
    return utf8.decode(_bytes.sublist(colon + 1, _pos), allowMalformed: true);
  }
}
