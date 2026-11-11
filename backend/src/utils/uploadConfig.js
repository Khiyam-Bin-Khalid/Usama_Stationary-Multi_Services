const multer = require('multer');
const env = require('../config/env');
const AppError = require('./AppError');

// Files are buffered in memory and handed to services/fileStorageService,
// which sends them to Cloudinary (or local disk when Cloudinary isn't set up).
const storage = multer.memoryStorage();

const ALLOWED_MIME = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];
const ALLOWED_IMAGE_MIME = ['image/jpeg', 'image/png', 'image/webp'];

function makeUpload(allowed, message) {
  return multer({
    storage,
    limits: { fileSize: env.maxUploadMb * 1024 * 1024, files: 1 },
    fileFilter: (req, file, cb) => {
      if (!allowed.includes(file.mimetype)) return cb(new AppError(400, message));
      cb(null, true);
    },
  });
}

const receiptUpload = makeUpload(ALLOWED_MIME, 'Only JPG, PNG, WEBP, or PDF receipts are allowed');
const productImageUpload = makeUpload(ALLOWED_IMAGE_MIME, 'Only JPG, PNG, or WEBP images are allowed');

module.exports = { receiptUpload, productImageUpload };
