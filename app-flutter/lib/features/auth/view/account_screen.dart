import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/core/widgets/app_bar_widget.dart';
import 'package:nebras_mobile_app/features/auth/provider/auth_provider.dart';
import 'package:nebras_mobile_app/features/saved/provider/saved_provider.dart';
import 'package:provider/provider.dart';

/// شاشة «حسابي» — تعرض كلّ بيانات المستخدم داخل التطبيق نفسه (دون أيّ
/// موقع خارجيّ)، وتتيح تسجيل الخروج و**حذف الحساب نهائيّاً** باحترافيّة.
///
/// التطبيق لا يخزّن بيانات شخصيّة في السحابة؛ المفضّلة وسجلّ المشاهدة
/// محليّة على الجهاز. لذا حذف الحساب = حذف هويّة Firebase + مسح كلّ
/// البيانات المحليّة، ويتمّ بالكامل داخل التطبيق.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBarWidget(title: 'account_title'.tr()),
      body: SafeArea(
        child: user == null
            ? _GuestBody()
            : ListView(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
                children: [
                  _AccountHeader(
                    name: user.displayName,
                    email: user.email,
                    photoUrl: user.photoUrl,
                  ),
                  24.sbh,
                  Text('account_details'.tr(),
                      style: TextStyles.heading3(context)),
                  12.sbh,
                  _InfoRow(label: 'account_name'.tr(), value: user.displayName),
                  _InfoRow(label: 'account_email'.tr(), value: user.email),
                  _InfoRow(label: 'account_id'.tr(), value: user.id),
                  _InfoRow(
                    label: 'account_signed_in_at'.tr(),
                    value: _formatDate(user.signedInAt),
                  ),
                  16.sbh,
                  Container(
                    padding: EdgeInsets.all(14.w),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      'account_data_note'.tr(),
                      style: TextStyles.smallText(context).copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.5,
                      ),
                    ),
                  ),
                  28.sbh,
                  OutlinedButton.icon(
                    onPressed: auth.isBusy ? null : () => _signOut(context),
                    icon: const Icon(Icons.logout_rounded),
                    label: Text('account_sign_out'.tr()),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                    ),
                  ),
                  12.sbh,
                  // حذف الحساب — إجراء مدمّر، بلون تحذيريّ + تأكيد صريح.
                  FilledButton.icon(
                    onPressed: auth.isBusy ? null : () => _confirmDelete(context),
                    icon: auth.isBusy
                        ? SizedBox(
                            width: 18.w,
                            height: 18.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.delete_forever_rounded),
                    label: Text('account_delete'.tr()),
                    style: FilledButton.styleFrom(
                      backgroundColor: ColorsManager.error,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  static String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _signOut(BuildContext context) async {
    await context.read<AuthProvider>().signOut();
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('account_delete_confirm_title'.tr()),
        content: Text('account_delete_confirm_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ColorsManager.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('account_delete'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final auth = context.read<AuthProvider>();
    // نمسح المفضّلة المحليّة أوّلاً (كامل بيانات المستخدم على الجهاز).
    try {
      await context.read<SavedProvider>().clearAll();
    } catch (_) {}
    if (!context.mounted) return;

    final ok = await auth.deleteAccount();
    if (!context.mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('account_deleted'.tr())),
      );
      Navigator.of(context).popUntil((r) => r.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ColorsManager.error,
          content: Text(auth.lastError ?? 'account_delete_failed'.tr()),
        ),
      );
    }
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.name,
    required this.email,
    required this.photoUrl,
  });

  final String name;
  final String email;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final initial = name.trim().isNotEmpty
        ? name.trim().characters.first.toUpperCase()
        : '?';
    return Row(
      children: [
        CircleAvatar(
          radius: 34.r,
          backgroundColor: scheme.primary.withValues(alpha: 0.15),
          backgroundImage: (photoUrl ?? '').trim().isNotEmpty
              ? NetworkImage(photoUrl!.trim())
              : null,
          child: (photoUrl ?? '').trim().isEmpty
              ? Text(
                  initial,
                  style: TextStyles.heading2(context)
                      .copyWith(color: scheme.primary),
                )
              : null,
        ),
        16.sbw,
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.heading3(context)),
              4.sbh,
              Text(email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyles.greysmallText(context)),
            ],
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120.w,
            child: Text(label, style: TextStyles.bodyBold(context)),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyles.body(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuestBody extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.no_accounts_rounded,
                size: 56.r,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            16.sbh,
            Text(
              'account_guest_note'.tr(),
              textAlign: TextAlign.center,
              style: TextStyles.body(context),
            ),
            20.sbh,
            FilledButton.icon(
              onPressed: () => context.read<AuthProvider>().signInWithGoogle(),
              icon: const Icon(Icons.login_rounded),
              label: Text('guest_prompt_action'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
