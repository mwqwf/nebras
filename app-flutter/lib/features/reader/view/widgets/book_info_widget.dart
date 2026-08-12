import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';

class BookInfoWidget extends StatelessWidget {
  const BookInfoWidget({
    super.key,
    required this.bookInfo,
    required this.bookProperty,
  });
  final String bookInfo;
  final String bookProperty;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(bookProperty, style: TextStyles.bodyPrimary(context)),
        12.sbw,
        Text(bookInfo, style: TextStyles.body(context)),
      ],
    );
  }
}
