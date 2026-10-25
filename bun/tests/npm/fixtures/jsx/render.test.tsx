// The JSX proof as a test (US1-1): a TSX component rendered with react-dom/server.

import { expect, test } from "bun:test";
import { renderToString } from "react-dom/server";
import { MARKUP } from "./expected.ts";
import { Counter } from "./render.tsx";

test("react-dom/server renders the component", () => {
  expect(renderToString(<Counter start={3} />)).toBe(MARKUP);
});
