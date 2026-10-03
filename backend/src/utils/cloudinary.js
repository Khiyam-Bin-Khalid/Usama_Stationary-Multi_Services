const { Readable } = require('stream');
const cloudinary = require('cloudinary').v2;
const env = require('../config/env');

if (env.cloudinary.enabled) {
  cloudinary.config({
    cloud_name: env.cloudinary.cloudName,
    api_key: env.cloudinary.apiKey,
    api_secret: env.cloudinary.apiSecret,
  });
}

function isCloudinaryConfigured() {
  return env.cloudinary.enabled;
}

// Streams an in-memory file buffer (from multer's memoryStorage) straight to
// Cloudinary — no temp file on disk. Rejects on network/API failure so the
// caller can fall back to local disk (offline desktop app).
function uploadBuffer(buffer, { folder }) {
  return new Promise((resolve, reject) => {
    const uploadStream = cloudinary.uploader.upload_stream({ folder, resource_type: 'image' }, (error, result) => {
      if (error) return reject(error);
      resolve(result);
    });
    Readable.from(buffer).pipe(uploadStream);
  });
}

module.exports = { isCloudinaryConfigured, uploadBuffer };
