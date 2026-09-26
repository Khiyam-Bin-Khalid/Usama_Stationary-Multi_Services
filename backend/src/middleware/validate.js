const AppError = require('../utils/AppError');

function validate(schema, property = 'body') {
  return (req, res, next) => {
    const { error, value } = schema.validate(req[property], { abortEarly: false, stripUnknown: true });
    if (error) {
      return next(new AppError(400, 'Validation failed', error.details.map((d) => d.message)));
    }
    req[property] = value;
    next();
  };
}

module.exports = validate;
