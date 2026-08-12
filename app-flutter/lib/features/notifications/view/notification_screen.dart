import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/routing/notification_navigator.dart';
import 'package:nebras_mobile_app/core/widgets/app_bar_widget.dart';
import 'package:nebras_mobile_app/core/widgets/empty_state_widget.dart';
import 'package:nebras_mobile_app/core/widgets/fade_in_list_item.dart';
import 'package:nebras_mobile_app/core/widgets/skeleton_loader.dart';
import 'package:nebras_mobile_app/features/notifications/provider/notfication_provider.dart';
import 'package:nebras_mobile_app/features/notifications/view/widget/notification_tile.dart';
import 'package:provider/provider.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<NotificationProvider>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Consumer<NotificationProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          appBar: AppBarWidget(
            title: 'Notifications'.tr(),
            leadingIcon: provider.isEmpty ? null : Icons.done_all_rounded,
            onLeadingIconPressed: provider.isEmpty
                ? null
                : () {
                    provider.markAllAsRead();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('All notifications marked as read'.tr()),
                      ),
                    );
                  },
          ),
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
              child: provider.isLoading
                  ? const NotificationSkeletonLoader()
                  : provider.isEmpty
                  ? EmptyStateWidget(message: 'No notifications available'.tr())
                  : ListView.separated(
                      itemCount: provider.notifications.length,
                      separatorBuilder: (_, _) => 12.sbh,
                      itemBuilder: (context, index) {
                        final item = provider.notifications[index];
                        return FadeInListItem(
                          index: index,
                          child: NotificationTile(
                            title: item.title,
                            body: item.body,
                            createdAt: item.createdAt,
                            dismissibleKey: ValueKey(item.id),
                            isRead: item.isRead,
                            onTap: () {
                              provider.markAsRead(item.id);
                              NotificationNavigator.instance.handle({
                                'type': item.type,
                                'contentId': item.contentId,
                                'title': item.title,
                                if ((item.sourceUrl ?? '').trim().isNotEmpty)
                                  'sourceUrl': item.sourceUrl,
                              });
                            },
                            onDismissed: (_) {
                              HapticFeedback.mediumImpact();
                              // نحتفظ بنسخة كاملة من الإشعار المحذوف
                              // محليّاً حتى نُتيح للمستخدم التراجع خلال
                              // مدّة قصيرة قبل اختفاء الـ SnackBar. الحذف
                              // في التخزين المحليّ يبقى فوريّاً لمرآة
                              // واجهة المستخدم الفعليّة.
                              final deleted = item;
                              provider.delete(deleted.id);
                              final messenger = ScaffoldMessenger.of(context);
                              messenger.clearSnackBars();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Notification deleted'.tr()),
                                  duration: const Duration(seconds: 3),
                                  action: SnackBarAction(
                                    label: 'Undo'.tr(),
                                    onPressed: () {
                                      provider.restore(deleted);
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
}
