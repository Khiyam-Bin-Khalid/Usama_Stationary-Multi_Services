const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
const path = require('path');
const rateLimit = require('express-rate-limit');
const env = require('./config/env');
const { notFoundHandler, errorHandler } = require('./middleware/errorHandler');

const authRoutes = require('./routes/authRoutes');
const userRoutes = require('./routes/userRoutes');
const productRoutes = require('./routes/productRoutes');
const saleRoutes = require('./routes/saleRoutes');
const syncRoutes = require('./routes/syncRoutes');
const reportRoutes = require('./routes/reportRoutes');
const promotionRoutes = require('./routes/promotionRoutes');
const orderRoutes = require('./routes/orderRoutes');
const paymentRoutes = require('./routes/paymentRoutes');
const categoryRoutes = require('./routes/categoryRoutes');
const shiftRoutes = require('./routes/shiftRoutes');
const notificationRoutes = require('./routes/notificationRoutes');
const auditRoutes = require('./routes/auditRoutes');
const discrepancyRoutes = require('./routes/discrepancyRoutes');
const inventoryRoutes = require('./routes/inventoryRoutes');
const notificationService = require('./services/notificationService');

// Spec §5: the Notification Service subscribes to domain events once, here,
// so every entry point (server, tests, seed) gets the same wiring.
notificationService.start();

const app = express();

const localhostOrigin = /^https?:\/\/(localhost|127\.0\.0\.1):\d+$/;

app.use(helmet());
app.use(
  cors({
    origin(origin, callback) {
      // No Origin header (server-to-server, curl, mobile/desktop app webviews).
      if (!origin) return callback(null, true);
      if (env.clientOrigins.includes('*')) return callback(null, true);
      if (env.clientOrigins.includes(origin)) return callback(null, true);
      // `flutter run -d chrome` / `-d web-server` binds a fresh random port
      // on every launch, so a fixed CLIENT_ORIGIN can never keep up in dev.
      if (env.nodeEnv === 'development' && localhostOrigin.test(origin)) return callback(null, true);
      return callback(null, false);
    },
    credentials: true,
  })
);
app.use(morgan(env.nodeEnv === 'development' ? 'dev' : 'combined'));

// Stripe webhook needs the raw body for signature verification, so it's
// mounted before the JSON body parser.
app.use('/api/payments/stripe/webhook', express.raw({ type: 'application/json' }));

app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true }));

app.use(
  '/api',
  rateLimit({ windowMs: 15 * 60 * 1000, max: 1000, standardHeaders: true, legacyHeaders: false, skip: () => env.nodeEnv === 'test' })
);

app.use('/uploads', express.static(path.join(__dirname, '..', env.uploadDir)));

app.get('/health', (req, res) => res.json({ status: 'ok', time: new Date().toISOString() }));

app.use('/api/auth', authRoutes);
app.use('/api/users', userRoutes);
app.use('/api/products', productRoutes);
app.use('/api/sales', saleRoutes);
app.use('/api/sync', syncRoutes);
app.use('/api/reports', reportRoutes);
app.use('/api/promotions', promotionRoutes);
app.use('/api/orders', orderRoutes);
app.use('/api/payments', paymentRoutes);
app.use('/api/categories', categoryRoutes);
app.use('/api/shifts', shiftRoutes);
app.use('/api/notifications', notificationRoutes);
app.use('/api/audit-logs', auditRoutes);
app.use('/api/inventory/discrepancies', discrepancyRoutes);
app.use('/api/inventory', inventoryRoutes);

app.use(notFoundHandler);
app.use(errorHandler);

module.exports = app;
