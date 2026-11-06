/**
 * Used by build-apk.cmd: prints MOBILE_API_BASE_URL from api/.env (no trailing newline logic in caller).
 * Requires: npm install in api/ (dotenv).
 */
const path = require("path");
const fs = require("fs");

const envPath = path.join(__dirname, "..", "api", ".env");
if (!fs.existsSync(envPath)) {
  process.exit(0);
}

require("dotenv").config({ path: envPath });
const u = (process.env.MOBILE_API_BASE_URL || "").trim();
if (u) process.stdout.write(u);
