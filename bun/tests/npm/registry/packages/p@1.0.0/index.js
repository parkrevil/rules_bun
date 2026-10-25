// Reports the q it loads and whether it can load its optional peer r.
let r = null;
let rError = null;
try {
  r = require("r").version;
} catch (error) {
  rError = String(error && error.message);
}
module.exports = { name: "p", version: "1.0.0", q: require("q").version, r, rError };
