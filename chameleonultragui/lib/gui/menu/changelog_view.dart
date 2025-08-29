import 'package:chameleonultragui/gui/component/error_page.dart';
import 'package:chameleonultragui/helpers/github.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:url_launcher/url_launcher.dart';

// Localizations
import 'package:chameleonultragui/generated/i18n/app_localizations.dart';

class ChangelogView extends StatefulWidget {
  const ChangelogView({super.key});

  @override
  ChangelogViewState createState() => ChangelogViewState();
}

class ChangelogViewState extends State<ChangelogView> {
  Future<List<ChangelogEntry>>? _changelogsFuture;

  @override
  void initState() {
    super.initState();
    _changelogsFuture = fetchChangelogs();
  }

  @override
  Widget build(BuildContext context) {
    var localizations = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(localizations.changelog),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: FutureBuilder<List<ChangelogEntry>>(
          future: _changelogsFuture,
          builder: (BuildContext context,
              AsyncSnapshot<List<ChangelogEntry>> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            } else if (snapshot.hasError) {
              return ErrorPage(errorMessage: snapshot.error.toString());
            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return Center(
                child: Text(localizations.no_changelogs_available),
              );
            } else {
              return ListView.separated(
                itemCount: snapshot.data!.length,
                separatorBuilder: (context, index) => const Divider(),
                itemBuilder: (context, index) {
                  final changelog = snapshot.data![index];
                  return _buildChangelogCard(changelog, localizations);
                },
              );
            }
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(localizations.ok),
        ),
      ],
    );
  }

  Widget _buildChangelogCard(
      ChangelogEntry changelog, AppLocalizations localizations) {
    final bool isUnreleased = changelog.version == "Unreleased";
    
    return Card(
      color: isUnreleased ? Colors.orange.withValues(alpha: 0.05) : null,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  changelog.version,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isUnreleased ? Colors.orange[700] : null,
                  ),
                ),
                if (isUnreleased) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      localizations.latest_commits,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isUnreleased ? localizations.latest_commits_from_main_branch : _formatDate(changelog.publishedAt),
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            if (changelog.changes.isNotEmpty) ...[
              Text(
                isUnreleased ? '${localizations.recent_commits}:' : '${localizations.changes}:',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 8),
              ...changelog.changes.map((change) => Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '• ',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Expanded(
                          child: _buildRichText(change),
                        ),
                      ],
                    ),
                  )),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  if (await canLaunchUrl(Uri.parse(changelog.url))) {
                    await launchUrl(Uri.parse(changelog.url));
                  }
                },
                child: Text(isUnreleased ? localizations.view_commits : localizations.view_full_release),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Widget _buildRichText(String text) {
    final List<TextSpan> spans = [];
    final RegExp combinedRegex = RegExp(
      r'(https?://[^\s]+)|(@[a-zA-Z0-9_-]+)',
      multiLine: true,
    );

    int lastMatchEnd = 0;

    for (final match in combinedRegex.allMatches(text)) {
      // Add text before the match
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: text.substring(lastMatchEnd, match.start),
          style: const TextStyle(
            fontSize: 14,
            fontStyle: FontStyle.normal,
          ),
        ));
      }

      final matchText = match.group(0)!;

      if (matchText.startsWith('http')) {
        // URL link
        spans.add(TextSpan(
          text: matchText,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.blue,
            decoration: TextDecoration.underline,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.parse(matchText);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
        ));
      } else if (matchText.startsWith('@')) {
        // User mention
        spans.add(TextSpan(
          text: matchText,
          style: const TextStyle(
            fontSize: 14,
            color: Colors.blue,
            fontWeight: FontWeight.w500,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final username = matchText.substring(1); // Remove @ symbol
              final uri = Uri.parse('https://github.com/$username');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
        ));
      }

      lastMatchEnd = match.end;
    }

    // Add remaining text
    if (lastMatchEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd),
        style: const TextStyle(
          fontSize: 14,
          fontStyle: FontStyle.normal,
        ),
      ));
    }

    return RichText(
      text: TextSpan(
        children: spans,
        style: const TextStyle(
          fontSize: 14,
          fontStyle: FontStyle.normal,
        ),
      ),
    );
  }
}
