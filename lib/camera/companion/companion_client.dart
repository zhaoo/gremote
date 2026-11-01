import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'companion_protocol.dart';
import 'companion_transport.dart';
import 'pairing_store.dart';

class CompanionException implements Exception {
  const CompanionException(this.code);
  final String code;
  @override
  String toString() => 'CompanionException($code)';
}

abstract interface class CompanionApi {
  String? get bootId;
  Future<CompanionCapabilities> capabilities();
  Future<CompanionSnapshot> state();
  Future<CompanionOperationReceipt> submit(Map<String, Object?> operation);
  Future<CompanionOperationReceipt> operation(String requestId);
  Future<FilmUploadReceipt> stageFilm(FilmUploadMetadata metadata);
  Future<FilmUploadReceipt> sendFilmChunk(
      String uploadId, int index, Uint8List bytes);
  Future<FilmUploadReceipt> filmUpload(String uploadId);
  Future<FilmUploadReceipt> verifyFilm(String uploadId);
  void invalidate();
}

class CompanionClient implements CompanionApi {
  CompanionClient(
      {required this.transport,
      required this.pairingStore,
      required this.identity,
      Map<String, dynamic>? contract,
      Future<void> Function()? busyWait})
      : contract = contract ?? companionContract,
        _busyWait = busyWait ??
            (() => Future<void>.delayed(const Duration(milliseconds: 250)));
  final Map<String, dynamic> contract;
  final Future<void> Function() _busyWait;
  final CompanionTransport transport;
  final PairingStore pairingStore;
  final PairingIdentity identity;
  String? _boot, _session;
  int _sequence = 0, _epoch = 0;
  Future<void> _tail = Future.value();
  @override
  String? get bootId => _boot;
  @override
  void invalidate() {
    _epoch++;
    _boot = null;
    _session = null;
    _sequence = 0;
  }

  Future<T> _serial<T>(Future<T> Function() run) {
    final epoch = _epoch;
    final result = _tail.then((_) {
      if (epoch != _epoch) throw const CompanionException('sessionChanged');
      return run();
    });
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  static String _hex(List<int> bytes) =>
      bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  bool _equal(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  Future<Map<String, dynamic>> _request(String method, String path,
      {Object? payload, Uint8List? binary, bool bootstrap = false}) async {
    final epoch = _epoch;
    if (!RegExp(
            r'^/m10v/v1/(capabilities|state|operations(/[a-f0-9]{32})?|films/stage(/[a-f0-9]{32}(/(verify|chunks/[0-2]))?)?)$')
        .hasMatch(path)) {
      throw const CompanionException('invalidCompanionTarget');
    }
    if (!bootstrap && (_boot == null || _session == null)) {
      throw const CompanionException('notPaired');
    }
    if (_sequence >= 0x7ffffffffffffffe) {
      throw const CompanionException('sessionExpired');
    }
    final sequence = bootstrap ? 0 : ++_sequence;
    final nonce = _hex(List.generate(16, (_) => Random.secure().nextInt(256)));
    final body = binary ??
        Uint8List.fromList(
            payload == null ? [] : utf8.encode(jsonEncode(payload)));
    if (body.length > 16384) throw const CompanionException('requestTooLarge');
    final canonical = [
      method,
      path,
      bootstrap ? '' : _boot!,
      bootstrap ? '' : _session!,
      '$sequence',
      nonce,
      sha256.convert(body).toString()
    ].join('\n');
    final signature = await pairingStore.sign(
        identity.instanceId, Uint8List.fromList(utf8.encode(canonical)));
    if (epoch != _epoch) throw const CompanionException('sessionChanged');
    final response = await transport
        .request(method: method, path: path, body: body, headers: {
      'X-M10V-KeyId': identity.keyId,
      'X-M10V-Boot': bootstrap ? '' : _boot!,
      'X-M10V-Session': bootstrap ? '' : _session!,
      'X-M10V-Seq': '$sequence',
      'X-M10V-Nonce': nonce,
      'X-M10V-Signature': _hex(signature),
      if (binary != null) 'X-M10V-Chunk-Hash': sha256.convert(body).toString()
    });
    if (epoch != _epoch) throw const CompanionException('sessionChanged');
    if (response.statusCode == 401) {
      throw const CompanionException('unauthorized');
    }
    final headers = {
      for (final e in response.headers.entries) e.key.toLowerCase(): e.value
    };
    final boot = headers['x-m10v-boot'],
        session = headers['x-m10v-session'],
        mac = headers['x-m10v-response-signature'];
    if (boot == null ||
        session == null ||
        mac == null ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(boot) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(session) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(mac) ||
        response.body.length > 16384) {
      throw const CompanionException('unauthenticatedResponse');
    }
    final signed = [
      'RESPONSE',
      method,
      path,
      boot,
      session,
      '$sequence',
      nonce,
      '${response.statusCode}',
      sha256.convert(response.body).toString()
    ].join('\n');
    final expected = _hex(await pairingStore.sign(
        identity.instanceId, Uint8List.fromList(utf8.encode(signed))));
    if (epoch != _epoch) throw const CompanionException('sessionChanged');
    if (!_equal(mac, expected)) {
      throw const CompanionException('unauthenticatedResponse');
    }
    if (!bootstrap && (boot != _boot || session != _session)) {
      invalidate();
      throw const CompanionException('sessionChanged');
    }
    final raw = jsonDecode(utf8.decode(response.body));
    if (raw is! Map<String, dynamic>) throw const FormatException('伴侣响应无效');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = (raw['error'] as Map?)?['code'];
      throw CompanionException(error is String && error.length <= 48
          ? error
          : 'companionUnavailable');
    }
    if (bootstrap) {
      final caps = CompanionCapabilities.fromJson(raw, contract: contract);
      if (caps.bootId != boot ||
          caps.sessionId != session ||
          caps.instanceId != identity.instanceId) {
        throw const CompanionException('identityMismatch');
      }
      _boot = boot;
      _session = session;
      _sequence = 0;
    }
    return raw;
  }

  void _snapshotIdentity(CompanionSnapshot value) {
    if (value.bootId != _boot || value.instanceId != identity.instanceId) {
      throw const CompanionException('identityMismatch');
    }
  }

  @override
  Future<CompanionCapabilities> capabilities() =>
      _serial(() async => CompanionCapabilities.fromJson(
          await _request('GET', '/m10v/v1/capabilities', bootstrap: true),
          contract: contract));
  @override
  Future<CompanionSnapshot> state() => _serial(() async {
        final epoch = _epoch;
        for (var attempt = 0;; attempt++) {
          try {
            final value = CompanionSnapshot.fromJson(
                await _request('GET', '/m10v/v1/state'),
                contract: contract);
            _snapshotIdentity(value);
            return value;
          } on CompanionException catch (error) {
            if (error.code != 'busy' || attempt >= 3) rethrow;
            await _busyWait();
            if (epoch != _epoch) {
              throw const CompanionException('sessionChanged');
            }
          }
        }
      });
  Future<CompanionOperationReceipt> _receipt(
      String method, String path, String id,
      {Object? payload}) async {
    final value = CompanionOperationReceipt.fromJson(
        await _request(method, path, payload: payload),
        contract: contract);
    if (value.requestId != id || value.bootId != _boot) {
      throw const CompanionException('identityMismatch');
    }
    if (value.snapshot != null) _snapshotIdentity(value.snapshot!);
    return value;
  }

  @override
  Future<CompanionOperationReceipt> submit(Map<String, Object?> operation) =>
      _serial(() async => _receipt(
          'POST', '/m10v/v1/operations', operation['requestId'] as String,
          payload: operation));
  @override
  Future<CompanionOperationReceipt> operation(String requestId) => _serial(
      () async => _receipt('GET', '/m10v/v1/operations/$requestId', requestId));
  @override
  Future<FilmUploadReceipt> stageFilm(FilmUploadMetadata metadata) =>
      _serial(() async {
        final receipt = FilmUploadReceipt.fromJson(await _request(
            'POST', '/m10v/v1/films/stage',
            payload: metadata.toJson()));
        if (receipt.wire['contentHash'] != metadata.contentHash ||
            receipt.wire['targetSlot'] != metadata.targetSlot ||
            receipt.wire['stableId'] != metadata.stableId) {
          throw const CompanionException('identityMismatch');
        }
        return receipt;
      });
  @override
  Future<FilmUploadReceipt> sendFilmChunk(
          String uploadId, int index, Uint8List bytes) =>
      _serial(() async {
        final value = FilmUploadReceipt.fromJson(await _request(
            'PUT', '/m10v/v1/films/stage/$uploadId/chunks/$index',
            binary: bytes));
        if (value.uploadId != uploadId) {
          throw const CompanionException('identityMismatch');
        }
        return value;
      });
  @override
  Future<FilmUploadReceipt> filmUpload(String uploadId) => _serial(() async {
        final value = FilmUploadReceipt.fromJson(
            await _request('GET', '/m10v/v1/films/stage/$uploadId'));
        if (value.uploadId != uploadId) {
          throw const CompanionException('identityMismatch');
        }
        return value;
      });
  @override
  Future<FilmUploadReceipt> verifyFilm(String uploadId) => _serial(() async {
        final value = FilmUploadReceipt.fromJson(
            await _request('POST', '/m10v/v1/films/stage/$uploadId/verify'));
        if (value.uploadId != uploadId) {
          throw const CompanionException('identityMismatch');
        }
        return value;
      });
}
