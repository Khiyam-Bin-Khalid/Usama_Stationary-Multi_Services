const env = require('../config/env');

// Only the one designated owner account (SUPERADMIN_EMAIL) may act as
// superadmin. If SUPERADMIN_EMAIL isn't configured (e.g. tests), the
// restriction is a no-op rather than locking out every superadmin.
function isSuperadminAllowed(email) {
  if (!env.superadmin.email) return true;
  return String(email).toLowerCase() === env.superadmin.email.toLowerCase();
}

module.exports = { isSuperadminAllowed };
