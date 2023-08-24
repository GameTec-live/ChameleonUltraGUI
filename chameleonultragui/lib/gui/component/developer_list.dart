import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class DeveloperList extends StatelessWidget {
  final List<Map<String, String>> avatars;

  const DeveloperList({super.key, required this.avatars});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Center(
        child: Wrap(
          alignment: WrapAlignment.center, // Center the items in each line
          children: List.generate(avatars.length, (index) {
            final avatar = avatars[index];
            return GestureDetector(
              onTap: () async {
                await launchUrl(
                    Uri.parse("https://github.com/${avatar['username']!}"));
              },
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundImage: NetworkImage(avatar['avatarUrl']!),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      avatar['name']!,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (avatar['description'] !=
                        "") // Use if instead of the spread operator
                      Text(avatar['description']!),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
