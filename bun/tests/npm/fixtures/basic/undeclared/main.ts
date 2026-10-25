// Imports c, which bun.lock lists and the workspace declares, but which this
// program does not depend on (US1-5).

import a from "a";
import c from "c";

console.log(JSON.stringify({ a, c }));
