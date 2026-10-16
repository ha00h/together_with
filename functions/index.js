const { initializeApp } = require('firebase-admin/app');
const { getDatabase } = require('firebase-admin/database');
const { getFirestore } = require('firebase-admin/firestore');
const { getStorage } = require('firebase-admin/storage');
const { onValueCreated } = require('firebase-functions/v2/database');
const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { defineSecret } = require('firebase-functions/params');

const { purgeExpiredRooms, purgeIdleRooms } = require('./cleanup');
const { stampExpiry, isExpiredFor } = require('./expiry');
const { buildVoiceToken } = require('./token');

const appCertificate = defineSecret('AGORA_APP_CERTIFICATE');
const appId = '72c3d9505b79415284246c4f2d983f96';

initializeApp();

exports.issueVoiceToken = onCall(
  {
    region: 'asia-northeast3',
    secrets: [appCertificate],
    timeoutSeconds: 15,
    memory: '256MiB',
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'sign-in-required');
    }
    const code = String(request.data?.code || '').trim().toUpperCase();
    const room = await getFirestore().collection('rooms').doc(code).get();
    if (!room.exists) {
      throw new HttpsError('not-found', 'room-not-found');
    }
    const hostUid = room.get('hostUid');
    if (typeof hostUid !== 'string' || hostUid.length === 0) {
      throw new HttpsError('failed-precondition', 'room-has-no-host');
    }
    if (isExpiredFor(room, request.auth.uid, Date.now())) {
      throw new HttpsError('permission-denied', 'room-expired');
    }
    try {
      return buildVoiceToken({
        appId,
        appCertificate: appCertificate.value().trim(),
        code,
        firebaseUid: request.auth.uid,
        hostUid,
      });
    } catch (error) {
      if (error.code === 'invalid-argument') {
        throw new HttpsError('invalid-argument', 'invalid-code');
      }
      throw new HttpsError('failed-precondition', 'token-unavailable');
    }
  },
);

exports.stampRoomExpiry = onValueCreated(
  {
    ref: '/rooms/{code}/startedAt',
    instance: 'together-with-view-default-rtdb',
    region: 'asia-southeast1',
    timeoutSeconds: 30,
    memory: '256MiB',
  },
  async (event) => {
    await stampExpiry({
      firestore: getFirestore(),
      code: event.params.code,
      startedAt: event.data.val(),
    });
  },
);

exports.purgeExpiredRooms = onSchedule(
  {
    schedule: 'every 60 minutes',
    region: 'asia-northeast3',
    timeZone: 'Asia/Seoul',
    timeoutSeconds: 300,
    memory: '256MiB',
  },
  async () => {
    const services = {
      database: getDatabase(),
      firestore: getFirestore(),
      bucket: getStorage().bucket(),
      nowMs: Date.now(),
    };
    const expired = await purgeExpiredRooms(services);
    const idle = await purgeIdleRooms(services);
    console.log(`purged ${expired.length} expired, ${idle.length} idle rooms`, {
      expired,
      idle,
    });
  },
);
