import 'package:flutter/material.dart';
import 'dart:ui';
import '../theme/app_theme.dart';
import 'glassmorphism_widget.dart';

// Shimmer effect for skeleton loaders
class ShimmerEffect extends StatefulWidget {
  final Widget child;
  final Color baseColor;
  final Color highlightColor;

  const ShimmerEffect({
    Key? key,
    required this.child,
    this.baseColor = const Color(0xFF2A2A2A),
    this.highlightColor = const Color(0xFF3A3A3A),
  }) : super(key: key);

  @override
  State<ShimmerEffect> createState() => _ShimmerEffectState();
}

class _ShimmerEffectState extends State<ShimmerEffect>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                widget.baseColor,
                widget.highlightColor,
                widget.baseColor,
              ],
              stops: [
                0.0,
                _animation.value.clamp(0.0, 1.0),
                1.0,
              ],
            ).createShader(bounds);
          },
          child: widget.child,
        );
      },
    );
  }
}

// Skeleton box widget
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    Key? key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ShimmerEffect(
      baseColor: AppTheme.secondaryDark.withOpacity(0.5),
      highlightColor: AppTheme.secondaryDark.withOpacity(0.8),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.secondaryDark.withOpacity(0.6),
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

// Product Card Skeleton
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      padding: const EdgeInsets.all(16),
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image skeleton
          ShimmerEffect(
            baseColor: AppTheme.secondaryDark.withOpacity(0.5),
            highlightColor: AppTheme.secondaryDark.withOpacity(0.8),
            child: Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: AppTheme.secondaryDark.withOpacity(0.6),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          
          // Title skeleton (2 lines)
          SkeletonBox(
            width: double.infinity,
            height: 16,
            borderRadius: 4,
          ),
          const SizedBox(height: 8),
          SkeletonBox(
            width: MediaQuery.of(context).size.width * 0.6,
            height: 16,
            borderRadius: 4,
          ),
          const SizedBox(height: 12),
          
          // Price and action buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Price skeleton
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonBox(
                    width: 100,
                    height: 20,
                    borderRadius: 4,
                  ),
                  const SizedBox(height: 4),
                  SkeletonBox(
                    width: 80,
                    height: 14,
                    borderRadius: 4,
                  ),
                ],
              ),
              
              // Action buttons skeleton
              Row(
                children: [
                  SkeletonBox(
                    width: 32,
                    height: 32,
                    borderRadius: 16,
                  ),
                  const SizedBox(width: 8),
                  SkeletonBox(
                    width: 32,
                    height: 32,
                    borderRadius: 16,
                  ),
                  const SizedBox(width: 8),
                  SkeletonBox(
                    width: 32,
                    height: 32,
                    borderRadius: 16,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Home Screen Skeleton (multiple product cards)
class HomeScreenSkeleton extends StatelessWidget {
  final int itemCount;

  const HomeScreenSkeleton({
    Key? key,
    this.itemCount = 3,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: ProductCardSkeleton(),
        );
      },
    );
  }
}

// Search Bar Skeleton
class SearchBarSkeleton extends StatelessWidget {
  const SearchBarSkeleton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GlassContainer(
        padding: EdgeInsets.zero,
        borderRadius: 16,
        child: ShimmerEffect(
          baseColor: AppTheme.secondaryDark.withOpacity(0.5),
          highlightColor: AppTheme.secondaryDark.withOpacity(0.8),
          child: Container(
            height: 50,
            decoration: BoxDecoration(
              color: AppTheme.secondaryDark.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    );
  }
}


