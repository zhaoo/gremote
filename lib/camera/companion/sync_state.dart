import 'companion_protocol.dart';
import 'three_way_merge.dart';

enum SyncConnectionStatus {
  offline,
  connecting,
  unsupported,
  ready,
  busy,
  error
}

enum SyncOperationStatus {
  draft,
  conflict,
  queued,
  applying,
  verifying,
  synced,
  unknown,
  failed
}

const _unset = Object();

class CompanionSyncState {
  const CompanionSyncState(
      {this.connectionStatus = SyncConnectionStatus.offline,
      this.operationStatus = SyncOperationStatus.draft,
      this.capabilities,
      this.snapshot,
      this.merge,
      this.message = '尚未连接 M10V 胶卷桥',
      this.readOnly = true,
      this.stale = true,
      this.rebootNeedsConfirmation = false,
      this.hasPreparedLoad = false,
      this.uploadBytes = 0});
  final SyncConnectionStatus connectionStatus;
  final SyncOperationStatus operationStatus;
  final CompanionCapabilities? capabilities;
  final CompanionSnapshot? snapshot;
  final MergeResult? merge;
  final String message;
  final bool readOnly, stale, rebootNeedsConfirmation, hasPreparedLoad;
  final int uploadBytes;
  bool get pending => {
        SyncOperationStatus.queued,
        SyncOperationStatus.applying,
        SyncOperationStatus.verifying,
        SyncOperationStatus.unknown
      }.contains(operationStatus);
  CompanionSyncState copyWith(
          {SyncConnectionStatus? connectionStatus,
          SyncOperationStatus? operationStatus,
          Object? capabilities = _unset,
          Object? snapshot = _unset,
          Object? merge = _unset,
          String? message,
          bool? readOnly,
          bool? stale,
          bool? rebootNeedsConfirmation,
          bool? hasPreparedLoad,
          int? uploadBytes}) =>
      CompanionSyncState(
          connectionStatus: connectionStatus ?? this.connectionStatus,
          operationStatus: operationStatus ?? this.operationStatus,
          capabilities: identical(capabilities, _unset)
              ? this.capabilities
              : capabilities as CompanionCapabilities?,
          snapshot: identical(snapshot, _unset)
              ? this.snapshot
              : snapshot as CompanionSnapshot?,
          merge: identical(merge, _unset) ? this.merge : merge as MergeResult?,
          message: message ?? this.message,
          readOnly: readOnly ?? this.readOnly,
          stale: stale ?? this.stale,
          rebootNeedsConfirmation:
              rebootNeedsConfirmation ?? this.rebootNeedsConfirmation,
          hasPreparedLoad: hasPreparedLoad ?? this.hasPreparedLoad,
          uploadBytes: uploadBytes ?? this.uploadBytes);
}
