import 'dart:convert';

import 'package:crypto/crypto.dart';

class ServerProfile {
  ServerProfile({required this.origin, this.username})
    : id = sha256
          .convert(utf8.encode('$origin\u0000${username ?? ''}'))
          .toString();

  final String id;
  final Uri origin;
  final String? username;

  String get displayOrigin => origin.toString();
}
