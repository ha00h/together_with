const test = require('node:test');
const assert = require('node:assert/strict');
const zlib = require('zlib');

const { agoraUid, buildVoiceToken } = require('./token');

const appId = '72c3d9505b79415284246c4f2d983f96';
const appCertificate = 'a'.repeat(32);

function tokenText(token) {
  const compressed = Buffer.from(token.slice(3), 'base64');
  return zlib.inflateSync(compressed).toString('latin1');
}

test('같은 사용자는 항상 같은 음성 번호를 받는다', () => {
  assert.equal(agoraUid('host-1'), agoraUid('host-1'));
  assert.notEqual(agoraUid('host-1'), agoraUid('guest-2'));
  assert.ok(agoraUid('host-1') > 0);
});

test('발표자만 송출 권한이 있고 토큰에는 수업 코드가 들어간다', () => {
  const host = buildVoiceToken({
    appId,
    appCertificate,
    code: '7gpab9',
    firebaseUid: 'host-1',
    hostUid: 'host-1',
  });
  const guest = buildVoiceToken({
    appId,
    appCertificate,
    code: '7GPAB9',
    firebaseUid: 'guest-2',
    hostUid: 'host-1',
  });

  assert.equal(host.publish, true);
  assert.equal(guest.publish, false);
  assert.equal(host.uid, agoraUid('host-1'));
  assert.notEqual(host.token, guest.token);
  assert.match(host.token, /^007/);
  assert.match(tokenText(host.token), /7GPAB9/);
  assert.match(tokenText(guest.token), /7GPAB9/);
  assert.equal(host.expireSeconds, 6 * 60 * 60);
});

test('수업 코드가 아니면 토큰을 만들지 않는다', () => {
  assert.throws(
    () =>
      buildVoiceToken({
        appId,
        appCertificate,
        code: 'abc',
        firebaseUid: 'host-1',
        hostUid: 'host-1',
      }),
    (error) => error.code === 'invalid-argument',
  );
});
