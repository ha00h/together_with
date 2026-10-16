const { Timestamp } = require('firebase-admin/firestore');

const { ROOM_LIFETIME_MS, isRoomCode } = require('./cleanup');

const NOT_FOUND = 5;

// Firestore and Storage rules cannot read RTDB, so the expiry is copied onto the room doc.
async function stampExpiry({ firestore, code, startedAt }) {
  if (!isRoomCode(code) || typeof startedAt !== 'number') return null;
  const expiresAt = Timestamp.fromMillis(startedAt + ROOM_LIFETIME_MS);
  try {
    await firestore.collection('rooms').doc(code).update({ expiresAt });
  } catch (error) {
    if (error.code === NOT_FOUND) return null;
    throw error;
  }
  return expiresAt;
}

function isExpiredFor(room, uid, nowMs) {
  const expiresAt = room.get('expiresAt');
  if (!expiresAt || typeof expiresAt.toMillis !== 'function') return false;
  return expiresAt.toMillis() <= nowMs && room.get('hostUid') !== uid;
}

module.exports = { stampExpiry, isExpiredFor };
