const Stripe = require('stripe');
const env = require('../config/env');

// Only constructed when a secret key is present. Until the user supplies
// their own Stripe keys in .env, callers should check env.stripe.enabled
// and fall back to manual-receipt / cash-on-delivery.
const stripeClient = env.stripe.enabled ? new Stripe(env.stripe.secretKey) : null;

module.exports = stripeClient;
