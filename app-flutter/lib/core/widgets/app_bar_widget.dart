import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';

class AppBarWidget extends StatelessWidget implements PreferredSizeWidget {
  const AppBarWidget({
    super.key,
    required this.title,
    this.leadingIcon,
    this.onLeadingIconPressed,
    this.showBackButton = true,
  });
  final String title;
  final IconData? leadingIcon;
  final VoidCallback? onLeadingIconPressed;
  final bool showBackButton;

  @override
  Widget build(BuildContext context) {
    final canGoBack = showBackButton && Navigator.canPop(context);

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      height: preferredSize.height,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          if (canGoBack)
            IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: Icon(Icons.arrow_back, size: 24.w),
            )
          else
            SizedBox(width: 16.w),
          16.sbw,
          Expanded(
            child: Text(
              title,
              style: TextStyles.heading3(context),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (leadingIcon != null)
            IconButton(
              onPressed: onLeadingIconPressed,
              icon: Icon(leadingIcon, size: 24.w),
            ),
        ],
      ),
    );
  }

  @override
  Size get preferredSize => Size.fromHeight(60.h);
}
