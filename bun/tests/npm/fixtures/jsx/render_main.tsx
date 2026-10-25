// The JSX proof as a program (US1-2): prints the markup and exits non-zero when
// it differs from the expected markup, the argument if one is given.

import { renderToString } from "react-dom/server";
import { MARKUP } from "./expected.ts";
import { Counter } from "./render.tsx";

const expected = process.argv[2] ?? MARKUP;
const markup = renderToString(<Counter start={3} />);
console.log(markup);
if (markup !== expected) {
  console.error(`markup mismatch: expected ${expected}`);
  process.exit(1);
}
