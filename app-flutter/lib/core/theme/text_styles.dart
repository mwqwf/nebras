import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_helper.dart';

class TextStyles {
  // HEADINGS
  static TextStyle heading1(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(fontSize: 26.sp, fontWeight: FontWeightHelper.bold)
        : GoogleFonts.poppins(
            fontSize: 26.sp,
            fontWeight: FontWeightHelper.bold,
          );
  }

  static TextStyle heading2(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(
            fontSize: 22.sp,
            fontWeight: FontWeightHelper.semibold,
          )
        : GoogleFonts.poppins(
            fontSize: 22.sp,
            fontWeight: FontWeightHelper.semibold,
          );
  }

  static TextStyle heading3(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(
            fontSize: 18.sp,
            fontWeight: FontWeightHelper.semibold,
          )
        : GoogleFonts.poppins(
            fontSize: 18.sp,
            fontWeight: FontWeightHelper.semibold,
          );
  }

  // BODY
  static TextStyle body(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(
            fontSize: 16.sp,
            fontWeight: FontWeightHelper.normal,
          )
        : GoogleFonts.poppins(
            fontSize: 16.sp,
            fontWeight: FontWeightHelper.normal,
          );
  }

  static TextStyle bodyPrimary(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(
            color: ColorsManager.primary,
            fontSize: 16.sp,
            fontWeight: FontWeightHelper.normal,
          )
        : GoogleFonts.poppins(
            color: ColorsManager.primary,
            fontSize: 16.sp,
            fontWeight: FontWeightHelper.normal,
          );
  }

  static TextStyle bodyBold(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(
            fontSize: 16.sp,
            fontWeight: FontWeightHelper.semibold,
          )
        : GoogleFonts.poppins(
            fontSize: 16.sp,
            fontWeight: FontWeightHelper.semibold,
          );
  }

  static TextStyle smallText(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(
            fontSize: 14.sp,
            fontWeight: FontWeightHelper.normal,
          )
        : GoogleFonts.poppins(
            fontSize: 14.sp,
            fontWeight: FontWeightHelper.normal,
          );
  }

  static TextStyle hintText(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(
            fontSize: 14.sp,
            fontWeight: FontWeight.normal,
            color: ColorsManager.greycolor,
          )
        : GoogleFonts.poppins(
            fontSize: 14.sp,
            fontWeight: FontWeight.normal,
            color: ColorsManager.greycolor,
          );
  }

  static TextStyle greysmallText(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(
            fontSize: 14.sp,
            fontWeight: FontWeight.normal,
            color: ColorsManager.greycolor,
          )
        : GoogleFonts.poppins(
            fontSize: 14.sp,
            fontWeight: FontWeight.normal,
            color: ColorsManager.greycolor,
          );
  }

  // BUTTONS
  static TextStyle button(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(fontSize: 16.sp, fontWeight: FontWeight.w600)
        : GoogleFonts.poppins(fontSize: 16.sp, fontWeight: FontWeight.w600);
  }

  // STATES
  static TextStyle success(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(
            fontSize: 15.sp,
            fontWeight: FontWeight.w500,
            color: Colors.green,
          )
        : GoogleFonts.poppins(
            fontSize: 15.sp,
            fontWeight: FontWeight.w500,
            color: Colors.green,
          );
  }

  static TextStyle error(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(
            fontSize: 15.sp,
            fontWeight: FontWeight.w500,
            color: Colors.redAccent,
          )
        : GoogleFonts.poppins(
            fontSize: 15.sp,
            fontWeight: FontWeight.w500,
            color: Colors.redAccent,
          );
  }

  static TextStyle warning(BuildContext context) {
    final locale = Localizations.localeOf(context).languageCode;
    return locale == 'ar'
        ? GoogleFonts.cairo(
            fontSize: 15.sp,
            fontWeight: FontWeight.w500,
            color: Colors.orange,
          )
        : GoogleFonts.poppins(
            fontSize: 15.sp,
            fontWeight: FontWeight.w500,
            color: Colors.orange,
          );
  }
}
