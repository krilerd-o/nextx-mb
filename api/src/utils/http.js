function sendSuccess(res, data, message = 'Success', statusCode = 200) {
  return res.status(statusCode).json({
    status: 'S',
    messagestatus: message,
    data,
  });
}

function sendError(res, errorCode, message, statusCode = 400) {
  return res.status(statusCode).json({
    status: 'E',
    messagestatus: 'Error',
    error_code: errorCode,
    message,
  });
}

module.exports = { sendSuccess, sendError };
