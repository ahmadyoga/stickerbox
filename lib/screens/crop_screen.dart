import 'dart:io';
import 'dart:typed_data';

import 'package:crop_your_image/crop_your_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../blocs/pack_detail/pack_detail_bloc.dart';
import '../blocs/pack_detail/pack_detail_event.dart';

class CropScreen extends StatefulWidget {
  const CropScreen({super.key, required this.sourcePath});

  final String sourcePath;

  @override
  State<CropScreen> createState() => _CropScreenState();
}

class _CropScreenState extends State<CropScreen> {
  final _controller = CropController();
  Uint8List? _imageBytes;

  @override
  void initState() {
    super.initState();
    File(widget.sourcePath).readAsBytes().then((bytes) {
      if (mounted) setState(() => _imageBytes = bytes);
    });
  }

  Future<void> _onCropped(CropResult result) async {
    switch (result) {
      case CropSuccess(:final croppedImage):
        await _saveAndDispatch(croppedImage);
      case CropFailure(:final cause):
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Crop failed: $cause')));
    }
  }

  Future<void> _saveAndDispatch(Uint8List croppedBytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final outputPath = p.join(
      dir.path,
      'stickers',
      '${DateTime.now().microsecondsSinceEpoch}_crop.png',
    );
    await Directory(p.dirname(outputPath)).create(recursive: true);
    await File(outputPath).writeAsBytes(croppedBytes);
    if (!mounted) return;
    context.read<PackDetailBloc>().add(TrayIconSet(outputPath));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _imageBytes;
    return Scaffold(
      backgroundColor: const Color(0xFF100D0A),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const Expanded(
                    child: Text(
                      'Crop tray icon',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: Text(
                      '1:1 · 96×96',
                      style: TextStyle(color: Colors.white54, fontSize: 11, fontFamily: 'JetBrains Mono'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: bytes == null
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : Padding(
                      padding: const EdgeInsets.all(24),
                      child: Crop(
                        controller: _controller,
                        image: bytes,
                        aspectRatio: 1,
                        onCropped: _onCropped,
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                'Tray icons are square. This crop is resized to 96×96 and saved as PNG.',
                style: TextStyle(color: Colors.white.withValues(alpha: .65), fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        minimumSize: const Size.fromHeight(56),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B57),
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(56),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: bytes == null ? null : () => _controller.crop(),
                      child: const Text('Use as tray icon'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
