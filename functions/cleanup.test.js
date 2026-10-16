const test = require('node:test');
const assert = require('node:assert/strict');

const {
  ROOM_LIFETIME_MS,
  CLEANUP_GRACE_MS,
  IDLE_ROOM_MS,
  cleanupCutoff,
  purgeExpiredRooms,
  purgeIdleRooms,
} = require('./cleanup');

const HOUR = 60 * 60 * 1000;

function fakeServer(rooms, createdAt = {}) {
  const calls = [];
  const live = { ...rooms };
  const database = {
    ref(path) {
      if (path === 'rooms') {
        const query = { start: -Infinity, end: Infinity, limit: Infinity };
        const chain = {
          orderByChild: () => chain,
          startAt: (value) => ((query.start = value), chain),
          endAt: (value) => ((query.end = value), chain),
          limitToFirst: (value) => ((query.limit = value), chain),
          get: async () => {
            const matched = Object.entries(live)
              .filter(([, room]) => {
                const started = room.startedAt;
                return (
                  typeof started === 'number' &&
                  started >= query.start &&
                  started <= query.end
                );
              })
              .slice(0, query.limit);
            return { val: () => Object.fromEntries(matched) };
          },
        };
        return chain;
      }
      const code = path.replace('rooms/', '');
      return {
        child: (name) => ({
          get: async () => ({ val: () => live[code]?.[name] ?? null }),
        }),
        remove: async () => {
          calls.push(['rtdb', path]);
          delete live[code];
        },
      };
    },
  };
  const firestore = {
    collection: (name) => ({
      doc: (id) => ({
        delete: async () => {
          calls.push(['firestore', `${name}/${id}`]);
          delete createdAt[id];
        },
      }),
      where: (field, op, value) => ({
        limit: () => ({
          get: async () => ({
            docs: Object.entries(createdAt)
              .filter(([, at]) => at <= value.getTime())
              .map(([id]) => ({ id })),
          }),
        }),
      }),
    }),
  };
  const bucket = {
    deleteFiles: async ({ prefix }) => calls.push(['storage', prefix]),
  };
  return { database, firestore, bucket, calls, live };
}

test('정리는 만료(24시간) 뒤 2일이 지난 방만 대상으로 한다', () => {
  assert.equal(ROOM_LIFETIME_MS, 24 * HOUR);
  assert.equal(CLEANUP_GRACE_MS, 48 * HOUR);
  assert.equal(cleanupCutoff(100 * HOUR), 28 * HOUR);
});

test('기간이 지난 방은 파일·방 정보·실시간 데이터 순서로 지운다', async () => {
  const now = 1000 * HOUR;
  const server = fakeServer({
    PASTA2: { startedAt: now - 73 * HOUR },
    NEWAB3: { startedAt: now - 71 * HOUR },
    WAKE45: { hostUid: 'host-1' },
  });

  const purged = await purgeExpiredRooms({ ...server, nowMs: now });

  assert.deepEqual(purged, ['PASTA2']);
  assert.deepEqual(server.calls, [
    ['storage', 'rooms/PASTA2/'],
    ['firestore', 'rooms/PASTA2'],
    ['rtdb', 'rooms/PASTA2'],
  ]);
  assert.deepEqual(Object.keys(server.live).sort(), ['NEWAB3', 'WAKE45']);
});

test('방 코드 형식이 아니면 건드리지 않고, 한 방이 실패해도 나머지는 지운다', async () => {
  const now = 1000 * HOUR;
  const server = fakeServer({
    'bad/x': { startedAt: 1 },
    FAKEA2: { startedAt: 2 },
    GREAT3: { startedAt: 3 },
  });
  const deleteFiles = server.bucket.deleteFiles;
  server.bucket.deleteFiles = async (options) => {
    if (options.prefix === 'rooms/FAKEA2/') throw new Error('boom');
    return deleteFiles(options);
  };
  const errors = console.error;
  console.error = () => {};
  try {
    const purged = await purgeExpiredRooms({ ...server, nowMs: now });
    assert.deepEqual(purged, ['GREAT3']);
  } finally {
    console.error = errors;
  }
  assert.ok(server.live['bad/x']);
  assert.ok(server.live.FAKEA2);
});

test('참여자가 없던 방은 발표자가 마지막으로 들어온 지 7일 지나면 지운다', async () => {
  assert.equal(IDLE_ROOM_MS, 7 * 24 * HOUR);
  const now = 1000 * HOUR;
  const day = 24 * HOUR;
  const server = fakeServer(
    {
      STALE2: { touchedAt: now - 8 * day },
      BUSYA3: { touchedAt: now - 2 * day },
      LEGACY: { hostUid: 'host-1' },
      USEDA4: { startedAt: now - 10 * HOUR },
      FRESH5: { touchedAt: now - HOUR },
    },
    {
      STALE2: now - 9 * day,
      BUSYA3: now - 30 * day,
      LEGACY: now - 8 * day,
      USEDA4: now - 9 * day,
      FRESH5: now - HOUR,
    },
  );

  const purged = await purgeIdleRooms({ ...server, nowMs: now });

  assert.deepEqual(purged.sort(), ['LEGACY', 'STALE2']);
  assert.deepEqual(Object.keys(server.live).sort(), ['BUSYA3', 'FRESH5', 'USEDA4']);
});
