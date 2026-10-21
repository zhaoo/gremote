import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../../darkroom/export/export_work_gate.dart';
import '../../imaging/imaging_engine.dart';
import '../../media/local/media_gateway.dart';
import '../model/film_roll.dart';
import 'contact_sheet_layout.dart';

class ContactSheetCell {
  const ContactSheetCell(this.item, this.thumbnail);
  final RollItem item;
  final Uint8List? thumbnail;
}

class ContactSheetRaster {
  const ContactSheetRaster(this.image, {required this.missingCount});
  final PreviewImage image;
  final int missingCount;
}

abstract interface class ContactSheetRasterizer {
  Future<ContactSheetRaster> rasterize(
      FilmRoll roll, ContactSheetPage page, List<ContactSheetCell> cells);
}

abstract interface class GeneratedJpegEncoder {
  Future<void> encode(PreviewImage image, String path,
      {ImagingCancelToken? cancel});
}

enum ContactSheetStatus { running, done, failed, cancelled }

class ContactSheetProgress {
  const ContactSheetProgress(this.status, this.pageIndex, this.totalPages,
      {this.missingCount = 0, this.uri, this.error});
  final ContactSheetStatus status;
  final int pageIndex, totalPages, missingCount;
  final String? uri;
  final Object? error;
}

class ContactSheetExporter {
  ContactSheetExporter(
      {required this.gateway,
      required this.rasterizer,
      required this.encoder,
      Future<Directory> Function()? tempDir})
      : tempDir = tempDir ?? getTemporaryDirectory;
  final MediaGateway gateway;
  final ContactSheetRasterizer rasterizer;
  final GeneratedJpegEncoder encoder;
  final Future<Directory> Function() tempDir;

  // Abandon read-only provider work on cancel/deadline. Its eventual result has
  // no access to a native cancel pointer, temporary files, or publication.
  Future<T> _read<T>(Future<T> work, ImagingCancelToken cancel) =>
      Future.any<T>([
        work.timeout(const Duration(seconds: 20)),
        cancel.whenCancelled.then<T>((_) => throw const _ReadCancelled()),
      ]);

  /// Consumes already rendered thumbnails. Never applies a film LUT again.
  /// Cancel tokens must remain alive until this stream finishes or is cancelled.
  Stream<ContactSheetProgress> export(FilmRoll roll, List<RollItem> items,
      {required ImagingCancelToken cancel, Set<int>? pageIndices}) async* {
    final pages = ContactSheetLayout.pages(items);
    final release = await ExportWorkGate.acquire();
    try {
      for (final page in pages) {
        if (pageIndices != null && !pageIndices.contains(page.index)) continue;
        String? path;
        var missing = 0;
        try {
          if (cancel.isCancelled) {
            yield ContactSheetProgress(
                ContactSheetStatus.cancelled, page.index, pages.length);
            return;
          }
          yield ContactSheetProgress(
              ContactSheetStatus.running, page.index, pages.length);
          final cells = <ContactSheetCell>[];
          for (final item in page.items) {
            if (cancel.isCancelled) break;
            Uint8List? thumbnail;
            try {
              if (item.mediaId != null) {
                final local = item.identity.instanceId == 'local-photo';
                final expected = item.identity.contentHash;
                final verified = !local ||
                    (expected != null &&
                        RegExp(r'^[a-f0-9]{64}$').hasMatch(expected) &&
                        await _read(
                                gateway.contentHash(item.mediaId!), cancel) ==
                            expected);
                if (verified && !cancel.isCancelled) {
                  thumbnail = await _read(
                      gateway.thumbnail(item.mediaId!, 324), cancel);
                  if (local &&
                      await _read(gateway.contentHash(item.mediaId!), cancel) !=
                          expected) {
                    thumbnail = null;
                  }
                }
              }
            } catch (_) {
              /* A single unavailable original keeps its position. */
            }
            if (thumbnail != null &&
                (thumbnail.isEmpty || thumbnail.length > 256 * 1024)) {
              thumbnail = null;
            }
            if (thumbnail == null) missing++;
            cells.add(ContactSheetCell(item, thumbnail));
          }
          if (cancel.isCancelled) {
            yield ContactSheetProgress(
                ContactSheetStatus.cancelled, page.index, pages.length);
            return;
          }
          final raster = await rasterizer.rasterize(roll, page, cells);
          final image = raster.image;
          missing = raster.missingCount;
          final dir = await tempDir();
          // mktemp-style directory avoids collisions across retries and old jobs.
          final ownDir = await dir.createTemp('gremote-contact-');
          path = '${ownDir.path}/page.jpg';
          if (!cancel.isCancelled) {
            await encoder.encode(image, path, cancel: cancel);
          }
          if (cancel.isCancelled) {
            yield ContactSheetProgress(
                ContactSheetStatus.cancelled, page.index, pages.length);
            return;
          }
          final uri = await gateway.publishGenerated(
              tempPath: path,
              displayName:
                  'GR_${roll.id.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "").substring(0, roll.id.replaceAll(RegExp(r"[^a-zA-Z0-9]"), "").length.clamp(0, 16))}_${page.index + 1}.jpg',
              width: image.width,
              height: image.height);
          yield ContactSheetProgress(
              ContactSheetStatus.done, page.index, pages.length,
              missingCount: missing, uri: uri);
        } catch (error) {
          yield ContactSheetProgress(
              cancel.isCancelled
                  ? ContactSheetStatus.cancelled
                  : ContactSheetStatus.failed,
              page.index,
              pages.length,
              missingCount: missing,
              error: error);
          if (cancel.isCancelled) return;
        } finally {
          if (path != null) {
            try {
              await File(path).parent.delete(recursive: true);
            } catch (_) {/* Best effort on storage errors. */}
          }
        }
      }
    } finally {
      release();
    }
  }
}

class _ReadCancelled implements Exception {
  const _ReadCancelled();
}
