const HOUR = 60 * 60 * 1000;
const ROOM_LIFETIME_MS = 24 * HOUR;
const CLEANUP_GRACE_MS = 48 * HOUR;
const IDLE_ROOM_MS = 7 * 24 * HOUR;

function cleanupCutoff(nowMs) {
  return nowMs - ROOM_LIFETIME_MS - CLEANUP_GRACE_MS;
}

function idleCutoff(nowMs) {
  return nowMs - IDLE_ROOM_MS;
}

function isRoomCode(code) {
  return (
    typeof code === 'string' && /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/.test(code)
  );
}

// RTDB goes last: it holds `startedAt`, so a failed run is retried next time.
async function purgeRoom(code, { database, firestore, bucket }) {
  if (!isRoomCode(code)) return false;
  await bucket.deleteFiles({ prefix: `rooms/${code}/` });
  await firestore.collection('rooms').doc(code).delete();
  await database.ref(`rooms/${code}`).remove();
  return true;
}

async function purgeExpiredRooms({ database, firestore, bucket, nowMs, limit = 200 }) {
  const snapshot = await database
    .ref('rooms')
    .orderByChild('startedAt')
    .startAt(1)
    .endAt(cleanupCutoff(nowMs))
    .limitToFirst(limit)
    .get();
  const codes = Object.keys(snapshot.val() || {});
  const purged = [];
  for (const code of codes) {
    try {
      if (await purgeRoom(code, { database, firestore, bucket })) {
        purged.push(code);
      }
    } catch (error) {
      console.error(`purge ${code} failed`, error);
    }
  }
  return purged;
}

// Rooms no participant ever joined: kept 7 days after the host's last visit.
async function purgeIdleRooms({ database, firestore, bucket, nowMs, limit = 500 }) {
  const cutoff = idleCutoff(nowMs);
  const snapshot = await firestore
    .collection('rooms')
    .where('createdAt', '<=', new Date(cutoff))
    .limit(limit)
    .get();
  const purged = [];
  for (const doc of snapshot.docs) {
    const code = doc.id;
    try {
      const room = database.ref(`rooms/${code}`);
      const started = (await room.child('startedAt').get()).val();
      if (started != null) continue;
      const touched = (await room.child('touchedAt').get()).val();
      if (typeof touched === 'number' && touched > cutoff) continue;
      if (await purgeRoom(code, { database, firestore, bucket })) {
        purged.push(code);
      }
    } catch (error) {
      console.error(`purge idle ${code} failed`, error);
    }
  }
  return purged;
}

module.exports = {
  ROOM_LIFETIME_MS,
  CLEANUP_GRACE_MS,
  IDLE_ROOM_MS,
  cleanupCutoff,
  idleCutoff,
  isRoomCode,
  purgeRoom,
  purgeExpiredRooms,
  purgeIdleRooms,
};
