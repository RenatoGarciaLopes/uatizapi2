import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class ChatSkeleton extends StatelessWidget {
  const ChatSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: 10,
      itemBuilder: (context, index) {
        final isRight = index % 2 == 0;
        return Align(
          alignment: isRight ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Shimmer.fromColors(
              baseColor: scheme.surfaceContainerHighest.withOpacity(0.6),
              highlightColor: scheme.surface.withOpacity(0.9),
              child: Container(
                width: 180 + (index % 3) * 20,
                height: 48,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}






