#!/usr/bin/env node
/**
 * Runs postman/UsamaStationary.postman_collection.json with Newman against
 * a throwaway server + in-memory MongoDB (never the real MONGODB_URI in
 * .env) so this can be run any time without touching production data.
 *
 * Usage: node scripts/run-e2e-postman.js
 */
const path = require('path');
const http = require('http');
const { spawn } = require('child_process');
const { MongoMemoryServer } = require('mongodb-memory-server');
const newman = require('newman');

const ROOT = path.join(__dirname, '..');
const PORT = 4100;
const SUPERADMIN_EMAIL = 'e2e-superadmin@example.com';
const SUPERADMIN_PASSWORD = 'E2ePassw0rd!';

function waitForHealth(url, timeoutMs = 20000) {
  const start = Date.now();
  return new Promise((resolve, reject) => {
    (function poll() {
      http
        .get(url, (res) => {
          if (res.statusCode === 200) return resolve();
          res.resume();
          retry();
        })
        .on('error', retry);
      function retry() {
        if (Date.now() - start > timeoutMs) return reject(new Error(`Server did not become healthy within ${timeoutMs}ms`));
        setTimeout(poll, 300);
      }
    })();
  });
}

async function main() {
  console.log('Starting in-memory MongoDB (isolated from the real database)...');
  const mongod = await MongoMemoryServer.create();
  const mongoUri = mongod.getUri();

  const env = {
    ...process.env,
    NODE_ENV: 'test', // skips rate limits + brute-force guard; this run logs in many times
    PORT: String(PORT),
    MONGODB_URI: mongoUri,
    JWT_ACCESS_SECRET: 'e2e_access_secret',
    JWT_REFRESH_SECRET: 'e2e_refresh_secret',
    SUPERADMIN_EMAIL,
    SUPERADMIN_PASSWORD,
    SUPERADMIN_NAME: 'E2E Superadmin',
    CLIENT_ORIGIN: '*',
    UPLOAD_DIR: 'uploads_e2e',
    // Left unset on purpose unless already exported by the shell: exercises
    // the local-disk fallback in productImageService when Cloudinary isn't
    // configured. Export CLOUDINARY_CLOUD_NAME/API_KEY/API_SECRET before
    // running this script to test the real Cloudinary path instead.
  };

  console.log('Seeding superadmin + default categories...');
  await new Promise((resolve, reject) => {
    const seed = spawn(process.execPath, ['src/utils/seed.js'], { cwd: ROOT, env, stdio: 'inherit' });
    seed.on('exit', (code) => (code === 0 ? resolve() : reject(new Error(`seed.js exited with code ${code}`))));
  });

  console.log(`Starting API server on port ${PORT}...`);
  const server = spawn(process.execPath, ['src/server.js'], { cwd: ROOT, env, stdio: 'inherit' });

  let exitCode = 1;
  try {
    await waitForHealth(`http://localhost:${PORT}/health`);
    console.log('Server is healthy. Running Postman collection with Newman...\n');

    exitCode = await new Promise((resolve) => {
      newman.run(
        {
          collection: path.join(ROOT, 'postman', 'UsamaStationary.postman_collection.json'),
          workingDir: ROOT, // so the formdata file path (postman/fixtures/...) resolves
          envVar: [
            { key: 'baseUrl', value: `http://localhost:${PORT}/api` },
            { key: 'superadminEmail', value: SUPERADMIN_EMAIL },
            { key: 'superadminPassword', value: SUPERADMIN_PASSWORD },
          ],
          reporters: ['cli'],
        },
        (err, summary) => {
          if (err) {
            console.error('Newman failed to run:', err);
            return resolve(1);
          }
          resolve(summary.run.failures.length > 0 ? 1 : 0);
        }
      );
    });
  } finally {
    server.kill();
    await mongod.stop();
  }

  process.exit(exitCode);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
