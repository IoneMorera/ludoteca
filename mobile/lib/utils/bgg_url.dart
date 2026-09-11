import 'package:url_launcher/url_launcher.dart';

String bggGameUrl(int bggId) => 'https://boardgamegeek.com/boardgame/$bggId';

Future<bool> openBggGame(int bggId) async {
  final uri = Uri.parse(bggGameUrl(bggId));
  if (await canLaunchUrl(uri)) {
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
  return false;
}
