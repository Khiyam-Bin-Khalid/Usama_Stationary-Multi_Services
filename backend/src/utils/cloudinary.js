const { Readable } = require('stream');
const cloudinary = require('cloudinary').v2;
const env = require('../config/env');

// Called once at server start, so missing credentials show up in the log right
// away: without them uploads fall back to local disk with no other warning.
function configureCloudinary() {
  if (!env.cloudinary.enabled) {
    console.error('❌ Cloudinary env vars missing! Images will be saved to local disk.'); // eslint-disable-line no-console
    return false;
  }

  cloudinary.config({
    cloud_name: env.cloudinary.cloudName,
    api_key: env.cloudinary.apiKey,
    api_secret: env.cloudinary.apiSecret,
  });

  console.log('✅ Cloudinary configured!'); // eslint-disable-line no-console
  return true;
}

function isCloudinaryConfigured() {
  return env.cloudinary.enabled;
}

// Streams an in-memory file buffer (from multer's memoryStorage) straight to
// Cloudinary — no temp file on disk. Rejects on network/API failure.
function uploadBuffer(buffer, { folder, resourceType = 'auto' }) {
  return new Promise((resolve, reject) => {
    const uploadStream = cloudinary.uploader.upload_stream({ folder, resource_type: resourceType }, (error, result) => {
      if (error) return reject(error);
      resolve(result);
    });
    Readable.from(buffer).pipe(uploadStream);
  });
}

module.exports = { cloudinary, configureCloudinary, isCloudinaryConfigured, uploadBuffer };
