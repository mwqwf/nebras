import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';

/// Search Bar Widget
/// Reusable search input with active state styling
class SearchBarWidget extends StatelessWidget {
  final TextEditingController controller;
  final String searchQuery;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final ValueChanged<String>? onSubmitted;

  /// عند تركها فارغة نستخدم مفتاح الترجمة "Search content..." حتى تتغيّر
  /// القيمة تلقائياً مع لغة الواجهة، بدلاً من نصّ إنجليزيّ مثبّت.
  final String? hintText;

  /// FocusNode اختياريّ يسمح للشاشة المستضيفة (مثلاً HomeScreen) بمتابعة
  /// متى يكون شريط البحث في حالة تركيز، لإظهار/إخفاء سجلّ البحث على غرار
  /// YouTube/Google.
  final FocusNode? focusNode;

  const SearchBarWidget({
    super.key,
    required this.controller,
    required this.searchQuery,
    required this.onChanged,
    required this.onClear,
    this.onSubmitted,
    this.hintText,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = searchQuery.isNotEmpty;
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
          color: isActive
              ? primaryColor.withValues(alpha: 0.3)
              : theme.dividerColor,
          width: 1.5,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        style: TextStyles.body(context),
        cursorColor: primaryColor,
        decoration: InputDecoration(
          hintText: hintText ?? 'Search content...'.tr(),
          hintStyle: TextStyles.hintText(context),
          prefixIcon: Icon(
            Icons.search_rounded,
            color: isActive ? primaryColor : theme.hintColor,
            size: 22.sp,
          ),
          suffixIcon: isActive
              ? IconButton(
                  icon: Icon(
                    Icons.clear_rounded,
                    color: theme.hintColor,
                    size: 20.sp,
                  ),
                  onPressed: onClear,
                  splashRadius: 20,
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16.w,
            vertical: 16.h,
          ),
        ),
      ),
    );
  }
}
