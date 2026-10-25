// A library that imports a package (US1-3): the target that depends on it gets
// the package through the library.

import a from "a";

export const versions = { a: a.version, b: a.b };
