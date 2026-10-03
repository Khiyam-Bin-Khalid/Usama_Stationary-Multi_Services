const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { updateUserSchema, changeRoleSchema, listUsersQuerySchema } = require('../validators/userValidators');
const userController = require('../controllers/userController');
const { ROLES } = require('../utils/constants');

const router = express.Router();

// Spec §2: register/delete/assign roles — Super Admin only.
router.use(authenticate, requireRole(ROLES.SUPERADMIN));

router.get('/', validate(listUsersQuerySchema, 'query'), userController.listUsers);
router.get('/:id', userController.getUser);
router.patch('/:id', validate(updateUserSchema), userController.updateUser);
router.patch('/:id/role', validate(changeRoleSchema), userController.changeRole);
router.delete('/:id', userController.deleteUser);

module.exports = router;
