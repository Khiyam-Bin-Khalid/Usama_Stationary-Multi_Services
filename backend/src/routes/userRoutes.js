const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { updateUserSchema, listUsersQuerySchema } = require('../validators/userValidators');
const userController = require('../controllers/userController');
const { ROLES } = require('../utils/constants');

const router = express.Router();

router.use(authenticate, requireRole(ROLES.SUPERADMIN, ROLES.ADMIN));

router.get('/', validate(listUsersQuerySchema, 'query'), userController.listUsers);
router.get('/:id', userController.getUser);
router.patch('/:id', validate(updateUserSchema), userController.updateUser);

module.exports = router;
