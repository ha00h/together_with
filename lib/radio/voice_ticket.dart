import 'package:cloud_functions/cloud_functions.dart';

class VoiceTicket {
  const VoiceTicket({required this.token, required this.uid});

  final String token;
  final int uid;
}

class VoiceTicketException implements Exception {
  const VoiceTicketException();
}

abstract class VoiceTicketIssuer {
  Future<VoiceTicket> issue(String code);
}

class FirebaseVoiceTicketIssuer implements VoiceTicketIssuer {
  FirebaseVoiceTicketIssuer({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final FirebaseFunctions _functions;

  @override
  Future<VoiceTicket> issue(String code) async {
    try {
      final result = await _functions.httpsCallable('issueVoiceToken').call({
        'code': code,
      });
      final data = result.data;
      if (data is! Map) throw const VoiceTicketException();
      final token = data['token'];
      final uid = data['uid'];
      if (token is! String || token.isEmpty || uid is! num) {
        throw const VoiceTicketException();
      }
      return VoiceTicket(token: token, uid: uid.toInt());
    } on VoiceTicketException {
      rethrow;
    } catch (_) {
      throw const VoiceTicketException();
    }
  }
}
