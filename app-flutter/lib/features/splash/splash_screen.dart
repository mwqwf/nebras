import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:nebras_mobile_app/core/theme/color_manager.dart';
import 'package:nebras_mobile_app/core/theme/text_styles.dart';
import 'package:nebras_mobile_app/features/auth/view/auth_gate.dart';

import 'package:video_player/video_player.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _videoController;
  late AnimationController _textAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;

  bool _isVideoInitialized = false;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _initializeTextAnimation();
    _scheduleNavigation();
  }

  void _initializeVideo() {
    _videoController =
        VideoPlayerController.asset('assets/videos/splash_intro.mp4')
          ..initialize()
              .then((_) {
                if (mounted) {
                  setState(() {
                    _isVideoInitialized = true;
                  });
                  _videoController.play();
                  _videoController.setLooping(false);
                  // الانتقال بمجرّد انتهاء الفيديو بدلاً من تأخير ثابت.
                  // نُضيف مستمعاً يكشف الوصول إلى آخر إطار.
                  _videoController.addListener(_onVideoTick);
                }
              })
              .catchError((error) {
                debugPrint('Video initialization error: $error');

                if (mounted) {
                  setState(() {
                    _isVideoInitialized = false;
                  });
                }
                // إن فشل الفيديو لا نعلّق المستخدم: ننتقل سريعاً.
                _navigateSoon(const Duration(milliseconds: 400));
              });
  }

  /// يُستدعى عند كلّ تحديث لحالة الفيديو — نلتقط لحظة انتهاء التشغيل.
  void _onVideoTick() {
    if (!mounted || _hasNavigated) return;
    final value = _videoController.value;
    final isFinished =
        value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration;
    if (isFinished) {
      _videoController.removeListener(_onVideoTick);
      _hasNavigated = true;
      _navigateToNextScreen();
    }
  }

  /// Initialize text animation (starts at 1.5s)
  void _initializeTextAnimation() {
    _textAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    // Fade: 0 → 1
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _textAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Slide: slight upward motion (14px → 0)
    _slideAnimation =
        Tween<Offset>(
          begin: const Offset(0, 0.03), // ~14px on typical screen
          end: Offset.zero,
        ).animate(
          CurvedAnimation(
            parent: _textAnimationController,
            curve: Curves.easeOutCubic,
          ),
        );

    // Scale: micro-scale (0.96 → 1.0)
    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.0).animate(
      CurvedAnimation(
        parent: _textAnimationController,
        curve: Curves.easeOutCubic,
      ),
    );

    // Start text animation at 1.5s
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _textAnimationController.forward();
      }
    });
  }

  /// جدولة انتقال "حدّ أعلى" (safety net) — لو فشل الفيديو في إطلاق حدث
  /// النهاية لأيّ سبب (مكتبة تتأخر، الجهاز ضعيف) لا نترك المستخدم محبوساً
  /// على السبلاش إلى الأبد. هذا التأخير لا يُلغي الانتقال الحدثيّ السريع
  /// الذي يحدث فور انتهاء الفيديو.
  void _scheduleNavigation() {
    _navigateSoon(const Duration(milliseconds: 3500));
  }

  void _navigateSoon(Duration timeout) {
    Future.delayed(timeout, () {
      if (mounted && !_hasNavigated) {
        _hasNavigated = true;
        _navigateToNextScreen();
      }
    });
  }

  /// Navigate with clean fade transition to `AuthGate`.
  /// نُحوّل دائمًا إلى `AuthGate` وهي التي تقرّر عرض `WelcomeScreen` أم
  /// `HomeShell` بحسب حالة الجلسة — هكذا نفصل قرار التوجيه عن السبلاش
  /// تمامًا، وتظلّ السبلاش معنيّة بالانطباع البصري فقط.
  void _navigateToNextScreen() {
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return const AuthGate();
        },
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _videoController.removeListener(_onVideoTick);
    _videoController.dispose();
    _textAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ColorsManager.whiteColor,
      body: SafeArea(
        child: Stack(
          children: [
            // Video Layer (centered, full-width)
            Center(
              child: _isVideoInitialized
                  ? AspectRatio(
                      aspectRatio: _videoController.value.aspectRatio,
                      child: VideoPlayer(_videoController),
                    )
                  : SizedBox(
                      width: double.infinity,
                      height: 400.h,
                      child: Center(
                        child: CircularProgressIndicator(
                          color: ColorsManager.primary,
                          strokeWidth: 2.5,
                        ),
                      ),
                    ),
            ),

            // Brand Name Layer (bottom-centered, animated)
            Positioned(
              left: 0,
              right: 0,
              bottom: 120.h,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: ScaleTransition(
                    scale: _scaleAnimation,
                    child: Text(
                      'Nebras'.tr(),
                      textAlign: TextAlign.center,
                      style: TextStyles.heading2(context),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
