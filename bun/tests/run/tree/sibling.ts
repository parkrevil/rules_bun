// Imports a sibling file this target does not declare; the import must fail.
import { undeclared } from "./undeclared.ts";

console.log(undeclared);
