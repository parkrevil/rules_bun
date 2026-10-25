// Loads a package, then imports one that bun.lock does not list.
import a from "a";
import pkg from "rules-bun-fixture-pkg";

console.log(a.version, pkg);
