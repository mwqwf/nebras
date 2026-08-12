import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/extensions/sized_boxextension.dart';
import 'package:nebras_mobile_app/core/widgets/language_card.dart';
import 'package:restart_app/restart_app.dart';

/// شاشة اختيار اللغة
///
/// تم حذف أعلام الدول بناءً على طلب المستخدم: يكفي تبديل اللغة يدوياً
/// من اسم اللغة فقط. نعرض في مكان العَلَم رمز اللغة (AR / EN / FR)
/// داخل دائرة لطيفة بلون تمييز التطبيق.
class LanguageScreen extends StatelessWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final currentLocale = context.locale;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: Text('Language Settings'.tr()), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            children: [
              LanguageCard(
                title: 'Arabic'.tr(),
                leadingLabel: 'AR',
                ontap: () {
                  context.setLocale(const Locale('ar'));
                  Restart.restartApp();
                },
                isSelected: currentLocale.languageCode == 'ar',
              ),
              12.sbh,
              LanguageCard(
                title: 'English'.tr(),
                leadingLabel: 'EN',
                ontap: () {
                  context.setLocale(const Locale('en'));
                  Restart.restartApp();
                },
                isSelected: currentLocale.languageCode == 'en',
              ),
              12.sbh,
              LanguageCard(
                title: 'French'.tr(),
                leadingLabel: 'FR',
                ontap: () {
                  context.setLocale(const Locale('fr'));
                  Restart.restartApp();
                },
                isSelected: currentLocale.languageCode == 'fr',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
