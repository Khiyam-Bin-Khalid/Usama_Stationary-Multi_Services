const { MongoMemoryServer } = require('mongodb-memory-server');
const mongoose = require('mongoose');

process.env.JWT_ACCESS_SECRET = 'test_access_secret';
process.env.JWT_REFRESH_SECRET = 'test_refresh_secret';
process.env.NODE_ENV = 'test';
// Tests create ad hoc superadmin accounts with random emails; make sure the
// real dev/prod SUPERADMIN_EMAIL from backend/.env doesn't leak in via
// dotenv and get them rejected by the single-superadmin-login restriction.
// (Set, not delete: dotenv only skips vars that already exist in process.env,
// so deleting them would let dotenv repopulate from the real .env file.)
process.env.SUPERADMIN_EMAIL = '';
process.env.SUPERADMIN_PASSWORD = '';

let mongod;

beforeAll(async () => {
  mongod = await MongoMemoryServer.create();
  process.env.MONGODB_URI = mongod.getUri();
  await mongoose.connect(process.env.MONGODB_URI);
});

afterEach(async () => {
  const collections = await mongoose.connection.db.collections();
  await Promise.all(collections.map((c) => c.deleteMany({})));
});

afterAll(async () => {
  await mongoose.disconnect();
  await mongod.stop();
});
