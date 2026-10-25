// Calls phantom-user, which requires b without declaring it (US1-7). The target
// declares b itself, so b is in its store, but not among phantom-user's
// dependencies.

import phantomUser from "phantom-user";

console.log(JSON.stringify(phantomUser()));
