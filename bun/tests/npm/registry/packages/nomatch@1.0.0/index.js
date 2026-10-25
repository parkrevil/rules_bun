for (const candidate of ["nomatch-sunos-x64", "nomatch-aix-ppc64"]) {
  try {
    module.exports = require(candidate);
  } catch {}
}
if (module.exports.name === undefined) {
  throw new Error("nomatch: no optional package matches this platform");
}
