const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { listNotificationsQuerySchema } = require('../validators/miscValidators');
const notificationController = require('../controllers/notificationController');
const { ROLES } = require('../utils/constants');

const router = express.Router();
// Staff are included because "new online order" alerts go to staff on duty
// (spec §5); customers get their own order/payment notifications. The
// service filters every query by the caller's role and user id.
router.use(authenticate, requireRole(ROLES.SUPERADMIN, ROLES.ADMIN, ROLES.STAFF, ROLES.CUSTOMER));

router.get('/', validate(listNotificationsQuerySchema, 'query'), notificationController.list);
router.get('/unread-count', notificationController.unreadCount);
router.post('/read-all', notificationController.markAllRead);
router.patch('/:id/read', notificationController.markRead);

module.exports = router;
