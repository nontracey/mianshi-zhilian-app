import 'package:flutter/material.dart';

class HeaderBar extends StatelessWidget {
  const HeaderBar({super.key, required this.title, required this.onProfile});

  final String title;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
            SizedBox(
              width: 280,
              child: SearchBar(
                hintText: '搜索知识点、标签、面试题',
                leading: const Icon(Icons.search),
              ),
            ),
            const SizedBox(width: 12),
            IconButton.filledTonal(
              onPressed: onProfile,
              icon: const Icon(Icons.person_outline),
            ),
          ],
        ),
      ),
    );
  }
}
