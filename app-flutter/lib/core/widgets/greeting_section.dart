import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/botttom_sheet_widget.dart';

/// Greeting Section Widget
/// Displays time-based greeting with emoji
/// and a friendly descriptive sentence (no auth, no user data)
class GreetingSection extends StatelessWidget {
  const GreetingSection({super.key});

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good Morning'.tr();
    } else if (hour < 17) {
      return 'Good Afternoon'.tr();
    } else {
      return 'Good Evening'.tr();
    }
  }

  String _getGreetingEmoji() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return '☀️'.tr();
    } else if (hour < 17) {
      return '👋'.tr();
    } else {
      return '🌙'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    final greeting = _getGreeting();
    final emoji = _getGreetingEmoji();

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      greeting,
                      style: TextStyles.body(context),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Text(emoji, style: TextStyle(fontSize: 16.sp)),
                ],
              ),
              SizedBox(height: 6.h),
              Text(
                'Explore the archives of knowledge'.tr(),
                style: TextStyles.heading3(context),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () {
            showModalBottomSheet(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              context: context,
              isScrollControlled: true,
              useSafeArea: true,
              builder: (sheetContext) {
                return Theme(
                  data: Theme.of(context),
                  child: const SettingsBottomSheetWidget(),
                );
              },
            );
          },
          icon: Icon(Icons.settings),
        ),
      ],
    );
  }
}
