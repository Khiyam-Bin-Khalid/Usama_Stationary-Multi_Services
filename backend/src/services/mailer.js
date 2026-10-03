// Email transport for notifications flagged with the "email" channel
// (spec §5). No SMTP provider is configured for this deployment yet, so the
// message is logged server-side; swap `sendMail` for nodemailer/SES/etc.
// without touching the Notification Service.
async function sendMail({ to, subject, text }) {
  console.log(`[mail] to=${to.join(',')} subject="${subject}" — ${text}`); // eslint-disable-line no-console
}

module.exports = { sendMail };
