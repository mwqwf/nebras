import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Icon(Icons.error, color: Theme.of(context).colorScheme.error),
            8.sbw,
            Text(
              'Download Failed'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
        ),
        8.sbh,
        OutlinedButton(onPressed: onRetry, child: Text('Retry'.tr())),
      ],
    );
  }
}
