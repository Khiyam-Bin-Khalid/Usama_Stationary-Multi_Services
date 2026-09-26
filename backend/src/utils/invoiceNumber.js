const { v4: uuid } = require('uuid');

// FBR-ready format placeholder: PREFIX-YYYYMMDD-XXXXXXXX
function generateInvoiceNumber(prefix) {
  const date = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const suffix = uuid().split('-')[0].toUpperCase();
  return `${prefix}-${date}-${suffix}`;
}

module.exports = { generateInvoiceNumber };
