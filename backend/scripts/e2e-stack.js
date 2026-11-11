/* eslint-disable no-console */
// Throwaway stack for the Flutter end-to-end tests (app/test/e2e): in-memory
// MongoDB, seeded data, and the real API on :4100. It never touches the Atlas
// database in .env.
//
// Default: Cloudinary points at a local stand-in on :4102 that checks each
// upload is signed and records it, so the real SDK path runs without spending
// real uploads. With --real-cloudinary the credentials in .env are used.
const http = require('http');
const path = require('path');
const crypto = require('crypto');
const { spawn, spawnSync } = require('child_process');
const { MongoMemoryServer } = require('mongodb-memory-server');

const realCloudinary = process.argv.includes('--real-cloudinary');
const API_PORT = 4100;
const FAKE_CLOUDINARY_PORT = 4102;
const uploads = [];

function startFakeCloudinary() {
  const server = http.createServer((req, res) => {
    if (req.url === '/__uploads') {
      res.setHeader('content-type', 'application/json');
      return res.end(JSON.stringify(uploads));
    }
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const body = Buffer.concat(chunks);
      const text = body.toString('latin1');
      const field = (name) => (text.match(new RegExp(`name="${name}"\\r\\n\\r\\n([^\\r]*)`)) || [])[1];
      const signed = Boolean(field('signature') && field('api_key') && field('timestamp'));
      const folder = field('folder');
      if (!signed) {
        res.statusCode = 401;
        return res.end(JSON.stringify({ error: { message: 'unsigned upload' } }));
      }
      const id = crypto.randomBytes(6).toString('hex');
      uploads.push({ url: req.url, folder, bytes: body.length, containsMarker: text.includes('E2E-IMAGE-MARKER') });
      res.setHeader('content-type', 'application/json');
      res.end(JSON.stringify({ public_id: `${folder}/${id}`, secure_url: `https://res.cloudinary.com/e2e/image/upload/${folder}/${id}.png` }));
    });
  });
  return new Promise((resolve) => { server.listen(FAKE_CLOUDINARY_PORT, '127.0.0.1', resolve); });
}

async function main() {
  const mongo = await MongoMemoryServer.create();
  const env = {
    ...process.env,
    PORT: String(API_PORT),
    NODE_ENV: 'test', // this suite signs in more often than the login rate limit allows
    MONGODB_URI: mongo.getUri('e2e'),
    SUPERADMIN_EMAIL: 'owner@example.com',
    SUPERADMIN_PASSWORD: 'OwnerPass123',
    SUPERADMIN_NAME: 'Shop Owner',
    UPLOAD_DIR: 'uploads_e2e',
    CLIENT_ORIGIN: '*', // `flutter test --platform chrome` serves from a random port
  };
  if (!realCloudinary) {
    await startFakeCloudinary();
    Object.assign(env, {
      CLOUDINARY_CLOUD_NAME: 'e2e',
      CLOUDINARY_API_KEY: 'e2ekey',
      CLOUDINARY_API_SECRET: 'e2esecret',
      CLOUDINARY_URL: `cloudinary://e2ekey:e2esecret@e2e?upload_prefix=http://127.0.0.1:${FAKE_CLOUDINARY_PORT}`,
    });
  }

  const cwd = path.join(__dirname, '..');
  const seeded = spawnSync('node', ['src/utils/seed.js'], { cwd, env, stdio: 'inherit' });
  if (seeded.status !== 0) throw new Error('Seeding failed');
  const api = spawn('node', ['src/server.js'], { cwd, env, stdio: 'inherit' });
  const stop = async () => {
    api.kill();
    await mongo.stop();
    process.exit(0);
  };
  process.on('SIGINT', stop);
  process.on('SIGTERM', stop);
  console.log(`E2E stack ready (${realCloudinary ? 'real' : 'stand-in'} Cloudinary)`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
