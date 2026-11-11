const path = require('path');
const fs = require('fs/promises');
const { v4: uuid } = require('uuid');
const env = require('../config/env');
const AppError = require('../utils/AppError');
const { isCloudinaryConfigured, uploadBuffer } = require('../utils/cloudinary');

const uploadDir = path.join(__dirname, '..', '..', env.uploadDir);

// Stores a multer memory-storage file and returns its public URL.
// Cloudinary when configured (a failure is surfaced, never silently written
// to the server's ephemeral disk); local disk only when Cloudinary is not
// configured at all (local/offline development).
async function storeFile(file, { folder }) {
  if (isCloudinaryConfigured()) {
    try {
      const result = await uploadBuffer(file.buffer, { folder: `usama-stationary/${folder}` });
      return result.secure_url;
    } catch (err) {
      console.error('Cloudinary upload failed:', err.message); // eslint-disable-line no-console
      throw new AppError(502, 'File upload failed, please try again');
    }
  }

  await fs.mkdir(uploadDir, { recursive: true });
  const name = `${uuid()}${path.extname(file.originalname).toLowerCase()}`;
  await fs.writeFile(path.join(uploadDir, name), file.buffer);
  return `/uploads/${name}`;
}

// Deletes a file previously saved to local disk by storeFile (a `/uploads/...`
// URL) once nothing references it, e.g. after the product photo was replaced
// by a Cloudinary upload. Cloudinary URLs and missing files are ignored; a
// failed delete is logged but never fails the request that triggered it.
async function removeLocalFile(url) {
  if (typeof url !== 'string' || !url.startsWith('/uploads/')) return;
  try {
    await fs.unlink(path.join(uploadDir, path.basename(url)));
  } catch (err) {
    if (err.code !== 'ENOENT') console.error('Could not delete local upload:', err.message); // eslint-disable-line no-console
  }
}

module.exports = { storeFile, removeLocalFile };
