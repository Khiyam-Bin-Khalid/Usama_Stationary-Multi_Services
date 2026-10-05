const path = require('path');
const fs = require('fs/promises');
const { isCloudinaryConfigured, uploadBuffer } = require('../utils/cloudinary');

// Cloudinary when configured and reachable (persistent CDN URL for the
// website); local disk otherwise — keeps the desktop app working the same
// way whether it's online or offline.
async function storeProductImage(file) {
  if (isCloudinaryConfigured()) {
    const buffer = await fs.readFile(file.path);
    let result;
    try {
      result = await uploadBuffer(buffer, { folder: 'usama-stationary/products' });
    } catch (err) {
      console.error('Cloudinary upload failed, saving locally instead:', err.message); // eslint-disable-line no-console
      return `/uploads/${path.basename(file.path)}`;
    }
    await fs.unlink(file.path);
    return result.secure_url;
  }

  return `/uploads/${path.basename(file.path)}`;
}

module.exports = { storeProductImage };
