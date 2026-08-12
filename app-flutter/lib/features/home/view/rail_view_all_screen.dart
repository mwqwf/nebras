import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/core/services/content_engagement_service.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/widgets/app_bar_widget.dart';
import 'package:nebras_mobile_app/core/widgets/youtube_content_card.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/content/view/content_router.dart.dart';
import 'package:nebras_mobile_app/features/home/model/home_rail.dart';

/// قائمة عموديّة لكلّ عناصر رفّ أفقيّ — «اعرض الكلّ».
class RailViewAllScreen extends StatelessWidget {
  const RailViewAllScreen({super.key, required this.rail});

  final HomeRail rail;

  Future<void> _open(BuildContext context, Content item) async {
    unawaited(
      InterestProfileService.instance.onContentConsumed(item),
    );
    ContentEngagementService.instance.recordContentOpened(item);
    await ContentRouter.open(
      context,
      item,
      contentContext: ContentContext.home,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBarWidget(title: rail.title),
      body: ListView.separated(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        itemCount: rail.items.length,
        separatorBuilder: (context, index) => SizedBox(height: 12.h),
        itemBuilder: (context, index) {
          final item = rail.items[index];
          return YouTubeContentCard(
            content: item,
            onTap: () => _open(context, item),
          );
        },
      ),
    );
  }
}
