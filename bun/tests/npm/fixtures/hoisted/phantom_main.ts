// Calls phantom-user, which requires b without declaring it. bun.lock has
// configVersion 0 (hoisted installs); the target declares b itself, so b is in
// its store, but not among phantom-user's dependencies.

import phantomUser from "phantom-user";

console.log(JSON.stringify(phantomUser()));
