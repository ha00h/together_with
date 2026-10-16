const crypto = require('crypto');
const { RtcRole, RtcTokenBuilder } = require('agora-token');

const CODE = /^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/;
const TOKEN_TTL_SECONDS = 6 * 60 * 60;

function agoraUid(firebaseUid) {
  const digest = crypto.createHash('sha256').update(String(firebaseUid)).digest();
  const uid = digest.readUInt32BE(0) & 0x7fffffff;
  return uid === 0 ? 1 : uid;
}

function buildVoiceToken({ appId, appCertificate, code, firebaseUid, hostUid }) {
  const channel = String(code || '').trim().toUpperCase();
  if (!CODE.test(channel)) {
    const error = new Error('invalid-code');
    error.code = 'invalid-argument';
    throw error;
  }
  if (!appId || !appCertificate) {
    const error = new Error('missing-credential');
    error.code = 'failed-precondition';
    throw error;
  }
  const uid = agoraUid(firebaseUid);
  const publish = firebaseUid === hostUid;
  const token = RtcTokenBuilder.buildTokenWithUid(
    appId,
    appCertificate,
    channel,
    uid,
    publish ? RtcRole.PUBLISHER : RtcRole.SUBSCRIBER,
    TOKEN_TTL_SECONDS,
    TOKEN_TTL_SECONDS,
  );
  return { token, uid, publish, expireSeconds: TOKEN_TTL_SECONDS };
}

module.exports = { CODE, TOKEN_TTL_SECONDS, agoraUid, buildVoiceToken };
