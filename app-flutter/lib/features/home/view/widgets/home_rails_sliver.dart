import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/media/content_context.dart';
import 'package:nebras_mobile_app/core/services/content_engagement_service.dart';
import 'package:nebras_mobile_app/core/services/interest_profile_service.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/youtube_content_card.dart';
import 'package:nebras_mobile_app/features/content/model/content_model.dart';
import 'package:nebras_mobile_app/features/content/view/content_router.dart.dart';
import 'package:nebras_mobile_app/features/home/model/home_rail.dart';
import 'package:nebras_mobile_app/core/extensions/navigation_extension.dart';
import 'package:nebras_mobile_app/features/home/providers/home_provider.dart';
import 'package:nebras_mobile_app/features/home/view/rail_view_all_screen.dart';
import 'package:provider/provider.dart';

/// رفوف أفقيّة للصفحة الرئيسيّة — انظر docs/CONTENT_ORDERING_AND_HOME.md.
class HomeRailsSliver extends StatelessWidget {
  const HomeRailsSliver({super.key});

  @override
  Widget build(BuildContext context) {
    final rails = context.watch<HomeProvider>().homeRails;
    if (rails.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final rail = rails[index];
          if (rail.isEmpty) return const SizedBox.shrink();
          // رفّ «تصفّح الأقسام» السفليّ أُزيل — أيّ رفّ من هذا النوع يُتجاهَل.
          if (rail.type == HomeRailType.browseSections) {
            return const SizedBox.shrink();
          }
          return _ContentHorizontalRail(rail: rail);
        },
        childCount: rails.length,
      ),
    );
  }
}

class _ContentHorizontalRail extends StatelessWidget {
  const _ContentHorizontalRail({required this.rail});

  static const int _viewAllThreshold = 6;

  final HomeRail rail;

  Future<void> _openContent(BuildContext context, Content item) async {
    unawaited(
      InterestProfileService.instance.onContentConsumed(item),
    );
    unawaited(
      ContentEngagementService.instance.recordContentOpened(item),
    );
    await ContentRouter.open(
      context,
      item,
      contentContext: ContentContext.home,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 20.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    rail.title,
                    style: TextStyles.heading3(context),
                  ),
                ),
                if (rail.items.length > _viewAllThreshold)
                  TextButton(
                    onPressed: () => context.push(
                      RailViewAllScreen(rail: rail),
                    ),
                    child: Text('home_rail_view_all'.tr()),
                  ),
              ],
            ),
          ),
          SizedBox(
            // الارتفاع يكفي للصورة 16:9 (280×157.5) + العنوان سطرَيْن +
            // السطر الفرعيّ، بعد إخفاء الوصف في الرفوف الأفقيّة (نمط
            // YouTube) لمنع تجاوز RenderFlex على بطاقات العناوين الطويلة.
            height: 250.h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: rail.items.length,
              separatorBuilder: (_, _) => SizedBox(width: 12.w),
              itemBuilder: (context, index) {
                final item = rail.items[index];
                return SizedBox(
                  width: 280.w,
                  child: YouTubeContentCard(
                    content: item,
                    onTap: () => _openContent(context, item),
                    showDescription: false,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

