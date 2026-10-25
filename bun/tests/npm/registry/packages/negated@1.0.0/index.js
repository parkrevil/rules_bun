let loaded = false;
try {
  require("negated-not-win");
  loaded = true;
} catch {}
module.exports = { loaded };
