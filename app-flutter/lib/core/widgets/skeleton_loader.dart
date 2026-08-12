import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Lightweight skeleton loader widgets — grey placeholder containers
/// No heavy dependencies, just simple shimmer-like placeholders

// ── Home Screen Skeleton ───────────────────────────────────────
class HomeSkeletonLoader extends StatelessWidget {
  const HomeSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title placeholder
          _SkeletonBox(width: 120.w, height: 18.h),
          SizedBox(height: 12.h),

          // Horizontal card row placeholder
          SizedBox(
            height: 190.h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, _) => SizedBox(width: 16.w),
              itemBuilder: (_, _) =>
                  _SkeletonBox(width: 160.w, height: 190.h, borderRadius: 16.r),
            ),
          ),
          SizedBox(height: 24.h),

          // Second section
          _SkeletonBox(width: 100.w, height: 18.h),
          SizedBox(height: 12.h),
          SizedBox(
            height: 190.h,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 3,
              separatorBuilder: (_, _) => SizedBox(width: 16.w),
              itemBuilder: (_, _) =>
                  _SkeletonBox(width: 160.w, height: 190.h, borderRadius: 16.r),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Search Screen Skeleton ─────────────────────────────────────
class SearchSkeletonLoader extends StatelessWidget {
  const SearchSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      shrinkWrap: true,
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, index) => Padding(
        padding: EdgeInsets.only(bottom: 12.h),
        child: Row(
          children: [
            _SkeletonBox(width: 64.w, height: 64.w, borderRadius: 8.r),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBox(width: double.infinity, height: 14.h),
                  SizedBox(height: 8.h),
                  _SkeletonBox(width: 100.w, height: 12.h),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Notification Screen Skeleton ───────────────────────────────
class NotificationSkeletonLoader extends StatelessWidget {
  const NotificationSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      child: Column(
        children: List.generate(
          6,
          (index) => Padding(
            padding: EdgeInsets.only(bottom: 12.h),
            child: Row(
              children: [
                _SkeletonBox(width: 44.w, height: 44.w, isCircle: true),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SkeletonBox(width: double.infinity, height: 14.h),
                      SizedBox(height: 6.h),
                      _SkeletonBox(width: 180.w, height: 12.h),
                      SizedBox(height: 4.h),
                      _SkeletonBox(width: 60.w, height: 10.h),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Saved Screen Skeleton ──────────────────────────────────────
class SavedSkeletonLoader extends StatelessWidget {
  const SavedSkeletonLoader({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 5,
      itemBuilder: (_, index) => Padding(
        padding: EdgeInsets.only(bottom: 12.h),
        child: Row(
          children: [
            _SkeletonBox(width: 80.w, height: 80.w, borderRadius: 8.r),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBox(width: double.infinity, height: 14.h),
                  SizedBox(height: 8.h),
                  _SkeletonBox(width: 80.w, height: 12.h),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Base Skeleton Box ──────────────────────────────────────────
class _SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;
  final bool isCircle;

  const _SkeletonBox({
    required this.width,
    required this.height,
    this.borderRadius = 8,
    this.isCircle = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.grey[800]
            : Colors.grey[200],
        shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: isCircle ? null : BorderRadius.circular(borderRadius),
      ),
    );
  }
}
