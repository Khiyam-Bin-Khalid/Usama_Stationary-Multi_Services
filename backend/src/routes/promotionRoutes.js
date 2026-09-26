const express = require('express');
const validate = require('../middleware/validate');
const { authenticate, requireRole } = require('../middleware/auth');
const { createPromotionSchema, updatePromotionSchema } = require('../validators/promotionValidators');
const promotionController = require('../controllers/promotionController');
const { ROLES } = require('../utils/constants');

const router = express.Router();

router.get('/active', promotionController.listActivePromotions);

router.use(authenticate, requireRole(ROLES.SUPERADMIN, ROLES.ADMIN));
router.get('/', promotionController.listAllPromotions);
router.post('/', validate(createPromotionSchema), promotionController.createPromotion);
router.patch('/:id', validate(updatePromotionSchema), promotionController.updatePromotion);

module.exports = router;
