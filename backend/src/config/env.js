require('dotenv').config();

function required(name, fallback) {
  const value = process.env[name] ?? fallback;
  if (value === undefined) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

module.exports = {
  port: Number(process.env.PORT || 4000),
  nodeEnv: process.env.NODE_ENV || 'development',
  // Comma-separated list, e.g. "http://localhost:5173,https://shop.example.com".
  clientOrigins: (process.env.CLIENT_ORIGIN || '*').split(',').map((o) => o.trim()).filter(Boolean),
  // First configured origin, used to build absolute URLs (e.g. Stripe redirect links).
  clientOrigin: (process.env.CLIENT_ORIGIN || '*').split(',')[0].trim(),

  mongodbUri: required('MONGODB_URI', 'mongodb://127.0.0.1:27017/usama_book_depot'),

  jwtAccessSecret: required('JWT_ACCESS_SECRET', 'dev_access_secret_change_me'),
  jwtRefreshSecret: required('JWT_REFRESH_SECRET', 'dev_refresh_secret_change_me'),
  jwtAccessExpires: process.env.JWT_ACCESS_EXPIRES || '15m',
  jwtRefreshExpires: process.env.JWT_REFRESH_EXPIRES || '30d',

  superadmin: {
    email: process.env.SUPERADMIN_EMAIL,
    password: process.env.SUPERADMIN_PASSWORD,
    name: process.env.SUPERADMIN_NAME || 'Superadmin',
  },

  stripe: {
    secretKey: process.env.STRIPE_SECRET_KEY || '',
    webhookSecret: process.env.STRIPE_WEBHOOK_SECRET || '',
    publishableKey: process.env.STRIPE_PUBLISHABLE_KEY || '',
    enabled: Boolean(process.env.STRIPE_SECRET_KEY),
  },

  uploadDir: process.env.UPLOAD_DIR || 'uploads',
  maxUploadMb: Number(process.env.MAX_UPLOAD_MB || 5),
};
