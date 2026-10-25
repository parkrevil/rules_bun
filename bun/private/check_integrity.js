// Checks a replacement archive of npm.replace_package against the integrity its
// bun.lock records (FR-026, research G3), with the algorithm the integrity
// names, and writes a stamp when they match. Run by the execution platform's
// Bun in a build action:
//
//   bun check_integrity.js <archive> <integrity> <package> <archive label> <stamp>
//
// Bun 1.4.2 writes an integrity as the digest's unpadded base64 followed by
// "==" (canary C-INTEGRITY), so the base64 values are compared without padding.

const [archive, expected, pkg, label, stamp] = process.argv.slice(2);
const ALGORITHMS = ["sha256", "sha384", "sha512"];

const dash = expected.indexOf("-");
const algorithm = dash === -1 ? "" : expected.slice(0, dash);
if (!ALGORITHMS.includes(algorithm)) {
  console.error(
    `rules_bun: bun.lock records the integrity "${expected}" for ${pkg}, whose algorithm is not one of ${ALGORITHMS.join(", ")}; the replacement archive ${label} cannot be checked`,
  );
  process.exit(1);
}

const digest = new Bun.CryptoHasher(algorithm).update(await Bun.file(archive).bytes()).digest("base64");
const unpadded = (value) => value.replace(/=+$/, "");
if (unpadded(digest) !== unpadded(expected.slice(dash + 1))) {
  console.error(
    `rules_bun: the replacement archive ${label} of ${pkg} has the integrity ${algorithm}-${digest}, but bun.lock records ${expected}; replace it with the archive the lockfile was written from`,
  );
  process.exit(1);
}
await Bun.write(stamp, `${pkg} ${expected}\n`);
