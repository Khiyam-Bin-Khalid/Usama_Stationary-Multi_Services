const AppError = require('../utils/AppError');
const asyncHandler = require('../utils/asyncHandler');
const notifications = require('../services/notificationService');

const list = asyncHandler(async (req, res) => {
  res.json(await notifications.listForUser(req.user, req.query));
});

const unreadCount = asyncHandler(async (req, res) => {
  res.json({ unread: await notifications.unreadCount(req.user) });
});

const markRead = asyncHandler(async (req, res) => {
  const n = await notifications.markRead(req.user, req.params.id);
  if (!n) throw new AppError(404, 'Notification not found');
  res.json({ ok: true });
});

const markAllRead = asyncHandler(async (req, res) => {
  res.json({ updated: await notifications.markAllRead(req.user) });
});

module.exports = { list, unreadCount, markRead, markAllRead };
