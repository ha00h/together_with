import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'active_room_store.dart';
import 'firebase_room_gateway.dart';
import 'private_stroke_store.dart';
import 'room_gateway.dart';

final roomGatewayProvider = Provider<RoomGateway>(
  (ref) => FirebaseRoomGateway(),
);

final livePushIntervalProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 40),
);

final activeRoomStoreProvider = Provider<ActiveRoomStore>(
  (ref) => FileActiveRoomStore(),
);

final privateStrokeStoreProvider = Provider<PrivateStrokeStore>(
  (ref) => FilePrivateStrokeStore(),
);
