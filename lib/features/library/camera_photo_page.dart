import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../camera/http/camera_files.dart';
import 'album_theme.dart';
import 'camera_gallery.dart';

/// Uses the ordinary camera downloader, restricted to this verified original.
class CameraPhotoPage extends StatelessWidget {
  const CameraPhotoPage(
      {super.key,
      required this.photo,
      required this.sourceCameraKey,
      this.cachedPreview});
  final CameraFile photo;
  final String sourceCameraKey;
  final Uint8List? cachedPreview;
  @override
  Widget build(BuildContext context) => Theme(
      data: albumTheme(context),
      child: Scaffold(
        appBar: AppBar(
            title: Text(photo.baseName, style: const TextStyle(fontSize: 16)),
            centerTitle: true),
        body: CameraGallery(
            initialFiles: [photo],
            sourceCameraKey: sourceCameraKey,
            singlePhoto: true,
            initialPreview: cachedPreview),
      ));
}
