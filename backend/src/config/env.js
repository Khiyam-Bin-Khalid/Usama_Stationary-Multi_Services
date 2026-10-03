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

  // Online-order pricing knobs (consolidated spec: delivery charges + tax
  // shown on the checkout summary). Flat fee applied to home-delivery orders.
  deliveryFee: Number(process.env.DELIVERY_FEE || 0),
  orderTaxRate: Number(process.env.ORDER_TAX_RATE || 0),

  uploadDir: process.env.UPLOAD_DIR || 'uploads',
  maxUploadMb: Number(process.env.MAX_UPLOAD_MB || 5),

  // Product photos go to Cloudinary when configured (persistent CDN storage
  // for the live website); the desktop app falls back to local disk when
  // offline or when these are left blank (dev/offline-only setups).
  cloudinary: {
    cloudName: process.env.CLOUDINARY_CLOUD_NAME || '',
    apiKey: process.env.CLOUDINARY_API_KEY || '',
    apiSecret: process.env.CLOUDINARY_API_SECRET || '',
    enabled: Boolean(process.env.CLOUDINARY_CLOUD_NAME && process.env.CLOUDINARY_API_KEY && process.env.CLOUDINARY_API_SECRET),
  },
};
