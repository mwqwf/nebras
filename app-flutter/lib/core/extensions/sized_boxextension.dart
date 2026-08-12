import 'package:flutter/widgets.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

extension SizedBoxScreenUtil on num {
  /// Responsive vertical spacing
  Widget get sbh => SizedBox(height: toDouble().h);

  /// Responsive horizontal spacing
  Widget get sbw => SizedBox(width: toDouble().w);
}
