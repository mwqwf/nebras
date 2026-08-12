import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:nebras_mobile_app/core/providers/sections_layout_provider.dart';
import 'package:provider/provider.dart';

/// زرّ تبديل شكل عرض الأقسام: قائمة ↔ شبكة (3 في صفّ).
///
/// يقرأ الحالة من [SectionsLayoutProvider] ويعرض أيقونة تناسب النمط
/// الحالي، فيفهم المستخدم أن الضغط سيبدّل النمط إلى الآخر. يتضمّن
/// تلميحاً (Tooltip) مترجماً حتى يكون الخيار مفهوماً في كل اللغات.
class SectionsLayoutToggle extends StatelessWidget {
  final Color? color;

  const SectionsLayoutToggle({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SectionsLayoutProvider>();
    final isGrid = provider.isGrid;
    return IconButton(
      onPressed: () => context.read<SectionsLayoutProvider>().toggle(),
      tooltip: isGrid ? 'List view'.tr() : 'Grid view'.tr(),
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 220),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          // الأيقونة تمثّل النمط البديل الذي سيُفعَّل عند الضغط، حتى يفهم
          // المستخدم وجهة الانتقال من النظرة الأولى.
          isGrid ? Icons.view_list_rounded : Icons.grid_view_rounded,
          key: ValueKey(isGrid),
          color: color,
        ),
      ),
    );
  }
}
