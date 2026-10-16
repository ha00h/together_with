const test = require('node:test');
const assert = require('node:assert/strict');

const { ROOM_LIFETIME_MS } = require('./cleanup');
const { stampExpiry, isExpiredFor } = require('./expiry');

function fakeFirestore(existing) {
  const updates = [];
  const firestore = {
    collection: (name) => ({
      doc: (id) => ({
        update: async (data) => {
          if (!existing.includes(id)) {
            throw Object.assign(new Error('not found'), { code: 5 });
          }
          updates.push([`${name}/${id}`, data]);
        },
      }),
    }),
  };
  return { firestore, updates };
}

function room(data) {
  return { get: (field) => data[field] };
}

test('첫 참여자 입장 시각에 24시간을 더해 방 문서에 남긴다', async () => {
  const { firestore, updates } = fakeFirestore(['HAPPY2']);
  const startedAt = 1_800_000_000_000;
  const stamped = await stampExpiry({ firestore, code: 'HAPPY2', startedAt });
  assert.equal(stamped.toMillis(), startedAt + ROOM_LIFETIME_MS);
  assert.equal(updates.length, 1);
  assert.equal(updates[0][0], 'rooms/HAPPY2');
  assert.equal(updates[0][1].expiresAt.toMillis(), startedAt + ROOM_LIFETIME_MS);
});

test('이미 지워진 방이나 잘못된 값은 건너뛴다', async () => {
  const { firestore, updates } = fakeFirestore([]);
  assert.equal(await stampExpiry({ firestore, code: 'GONEA2', startedAt: 1 }), null);
  assert.equal(await stampExpiry({ firestore, code: 'bad', startedAt: 1 }), null);
  assert.equal(await stampExpiry({ firestore, code: 'GONEA2', startedAt: 'x' }), null);
  assert.equal(updates.length, 0);
});

test('만료 뒤에는 발표자만 통과한다', () => {
  const expiresAt = { toMillis: () => 1000 };
  const expired = room({ hostUid: 'host', expiresAt });
  assert.equal(isExpiredFor(expired, 'guest', 1000), true);
  assert.equal(isExpiredFor(expired, 'host', 1000), false);
  assert.equal(isExpiredFor(expired, 'guest', 999), false);
  assert.equal(isExpiredFor(room({ hostUid: 'host' }), 'guest', 5000), false);
});
