// Imports a, which the root and w1 declare but w2 does not (US4-1).

import a from "a";
import c from "c";

console.log(JSON.stringify({ a, c }));
