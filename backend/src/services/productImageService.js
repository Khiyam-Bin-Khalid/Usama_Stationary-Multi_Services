const path = require('path');
const fs = require('fs/promises');
const { v4: uuid } = require('uuid');
const env = require('../config/env');
const { isCloudinaryConfigured, uploadBuffer } = require('../utils/cloudinary');

const uploadDir = path.join(__dirname, '..', '..', env.uploadDir);

async function saveLocally(file) {
  await fs.mkdir(uploadDir, { recursive: true });
  const filename = `${uuid()}${path.extname(file.originalname)}`;
  await fs.writeFile(path.join(uploadDir, filename), file.buffer);
  return `/uploads/${filename}`;
}

// Cloudinary when configured and reachable (persistent CDN URL for the
// website); local disk otherwise — keeps the desktop app working the same
// way whether it's online or offline.
async function storeProductImage(file) {
  if (isCloudinaryConfigured()) {
    try {
      const result = await uploadBuffer(file.buffer, { folder: 'usama-stationary/products' });
      return result.secure_url;
    } catch (err) {
      console.error('Cloudinary upload failed, saving locally instead:', err.message); // eslint-disable-line no-console
    }
  }
  return saveLocally(file);
}

module.exports = { storeProductImage };
