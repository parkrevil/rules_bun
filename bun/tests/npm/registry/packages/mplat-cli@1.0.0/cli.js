let helper = "none";
try {
  helper = require("mplat-helper").name;
} catch {}
console.log(`mplat-cli ${helper}`);
