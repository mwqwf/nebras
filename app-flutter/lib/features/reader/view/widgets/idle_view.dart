import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';

class IdleView extends StatelessWidget {
  const IdleView({super.key, required this.onRead, required this.onDownload});
  final VoidCallback onRead;
  final VoidCallback onDownload;
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton(onPressed: onRead, child: Text("Read".tr())),
        ),
        12.sbw,
        Expanded(
          child: OutlinedButton.icon(
            onPressed: onDownload,
            label: Text("Download".tr()),
            icon: const Icon(Icons.download),
          ),
        ),
      ],
    );
  }
}
