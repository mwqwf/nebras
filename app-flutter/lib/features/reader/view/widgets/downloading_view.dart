import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';

class DownloadingView extends StatelessWidget {
  const DownloadingView({
    super.key,
    required this.progress,
    required this.onCancel,
  });

  final double progress;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text("Downloading...".tr()),
            TextButton(
              onPressed: onCancel,
              child: Text(
                "Cancel".tr(),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
        8.sbh,
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: progress),
          duration: const Duration(milliseconds: 300),
          builder: (_, value, child) {
            return LinearProgressIndicator(value: value);
          },
        ),
        6.sbh,
        Text("${(progress * 100).toStringAsFixed(0)}%"),
      ],
    );
  }
}
