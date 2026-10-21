import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gremote/camera/companion/film_transfer.dart';
void main(){
 final fixture=File('test/fixtures/custom-film.m10vfilm').readAsBytesSync();final renderer=(jsonDecode(utf8.decode(fixture)) as Map)['metadata']['rendererHash'] as String;
 test('shared Node exporter fixture parses without executable or target-slot fields',(){final film=FilmTransfer.parse(fixture,expectedRenderer:renderer);expect(film.stableId,79);expect(film.name,'FIXTURE');expect(film.chunk(0),hasLength(4096));expect(film.chunk(2),hasLength(4096));expect(()=>film.chunk(0)[0]=0,throwsUnsupportedError);expect(film.recipe('0'*64).customHash,film.contentHash);});
 test('old renderer, metadata injection and valid-CRC damaged inner digest reject',(){expect(()=>FilmTransfer.parse(fixture,expectedRenderer:'0'*64),throwsFormatException);final value=jsonDecode(utf8.decode(fixture)) as Map<String,dynamic>;value['metadata']['targetSlot']=0;expect(()=>FilmTransfer.parse(Uint8List.fromList(utf8.encode(jsonEncode(value))),expectedRenderer:renderer),throwsFormatException);value['metadata'].remove('targetSlot');final record=base64Decode(value['recordBase64'] as String);record[6656]^=1;var crc=0xffffffff;for(final b in record.sublist(0,12284)){crc^=b;for(var bit=0;bit<8;bit++){crc=(crc>>>1)^(0xedb88320&-(crc&1));}}ByteData.sublistView(record).setUint32(12284,~crc&0xffffffff,Endian.little);value['recordBase64']=base64Encode(record);value['metadata']['contentHash']=sha256.convert(record).toString();expect(()=>FilmTransfer.parse(Uint8List.fromList(utf8.encode(jsonEncode(value))),expectedRenderer:renderer),throwsFormatException);});
}
