// Unit tests of graph.ts's comparison (research R8, contract "Failure text").

import { expect, test } from "bun:test";
import { compare, type Graph } from "./graph.ts";

const entry = (name: string, version: string, links: Record<string, string> = {}) => ({ name, version, links });

test("graphs equal up to entry order and indices are equal", () => {
  const ruleset: Graph = {
    holders: { "": { a: "e:0", b: "e:1" } },
    entries: [entry("a", "1.0.0", { b: "e:1" }), entry("b", "1.0.0")],
  };
  const bun: Graph = {
    holders: { "": { a: "e:1", b: "e:0" } },
    entries: [entry("b", "1.0.0"), entry("a", "1.0.0", { b: "e:0" })],
  };
  expect(compare("p", ruleset, bun)).toBeUndefined();
});

test("one entry against two entries of one name@version with different peer bindings differ", () => {
  // Bun: p@1.0.0 twice, once with q@1.0.0 and once with q@2.0.0.
  const bun: Graph = {
    holders: { "": { u: "e:0", v: "e:1" } },
    entries: [
      entry("u", "1.0.0", { p: "e:2" }),
      entry("v", "1.0.0", { p: "e:3" }),
      entry("p", "1.0.0", { q: "e:4" }),
      entry("p", "1.0.0", { q: "e:5" }),
      entry("q", "1.0.0"),
      entry("q", "2.0.0"),
    ],
  };
  // Ruleset: one p@1.0.0 with q@1.0.0 for both.
  const ruleset: Graph = {
    holders: { "": { u: "e:0", v: "e:1" } },
    entries: [entry("u", "1.0.0", { p: "e:2" }), entry("v", "1.0.0", { p: "e:2" }), entry("p", "1.0.0", { q: "e:3" }), entry("q", "1.0.0")],
  };
  expect(compare("p", ruleset, bun)).toBe(
    'p: p@1.0.0 links "q" to q@1.0.0, Bun links it to q@2.0.0',
  );
});

test("entry counts count: two identical entries against one", () => {
  const bun: Graph = { holders: { "": { a: "e:0", b: "e:1" } }, entries: [entry("a", "1.0.0", { x: "e:2" }), entry("b", "1.0.0", { x: "e:2" }), entry("x", "1.0.0")] };
  const ruleset: Graph = {
    holders: { "": { a: "e:0", b: "e:1" } },
    entries: [entry("a", "1.0.0", { x: "e:2" }), entry("b", "1.0.0", { x: "e:3" }), entry("x", "1.0.0"), entry("x", "1.0.0")],
  };
  expect(compare("p", ruleset, bun)).toBe("p: x@1.0.0 is 2 entries in the ruleset, Bun installs it as 1");
});

test("a holder linking a different target differs", () => {
  const bun: Graph = { holders: { "": { b: "e:0" } }, entries: [entry("b", "2.0.0")] };
  const ruleset: Graph = { holders: { "": { b: "e:0" } }, entries: [entry("b", "1.0.0")] };
  expect(compare("p", ruleset, bun)).toBe('p: the root links "b" to b@1.0.0, Bun links it to b@2.0.0');
});

test("a missing link differs", () => {
  const bun: Graph = { holders: { "": {}, "packages/w": { b: "e:0" } }, entries: [entry("b", "1.0.0")] };
  const ruleset: Graph = { holders: { "": {}, "packages/w": {} }, entries: [] };
  expect(compare("p", ruleset, bun)).toBe('p: workspace "packages/w" links "b" to no link, Bun links it to b@1.0.0');
});

test("an extra link differs", () => {
  const bun: Graph = { holders: { "": { a: "e:0" } }, entries: [entry("a", "1.0.0")] };
  const ruleset: Graph = { holders: { "": { a: "e:0" } }, entries: [entry("a", "1.0.0", { state: "e:1" }), entry("state", "1.0.0")] };
  expect(compare("p", ruleset, bun)).toBe('p: a@1.0.0 links "state" to state@1.0.0, Bun links it to no link');
});

test("a workspace target is compared by path", () => {
  const bun: Graph = { holders: { "": { u: "e:0" }, "packages/m": {} }, entries: [entry("u", "1.0.0", { m: "w:packages/m" })] };
  const ruleset: Graph = { holders: { "": { u: "e:0" }, "packages/m": {} }, entries: [entry("u", "1.0.0")] };
  expect(compare("p", ruleset, bun)).toBe('p: u@1.0.0 links "m" to no link, Bun links it to workspace "packages/m"');
});

test("a holder on one side only differs", () => {
  const bun: Graph = { holders: { "": {}, "packages/w": {} }, entries: [] };
  const ruleset: Graph = { holders: { "": {} }, entries: [] };
  expect(compare("p", ruleset, bun)).toBe('p: workspace "packages/w" is a holder in Bun only');
});

test("a package at no registry version is identified by its name", () => {
  const bun: Graph = { holders: { "": { local: "e:0" } }, entries: [entry("local", "1.0.0")] };
  const ruleset: Graph = { holders: { "": { local: "e:0" } }, entries: [entry("local", "file:local")] };
  expect(compare("p", ruleset, bun)).toBeUndefined();
});

test("an entry whose status fails analysis in the ruleset differs", () => {
  const bun: Graph = { holders: { "": { "ident-a": "e:0" } }, entries: [entry("ident-a", "1.0.0")] };
  const ruleset: Graph = {
    holders: { "": { "ident-a": "e:0" } },
    entries: [{ ...entry("ident-a", "1.0.0"), status: 'it needs the peer "state", which nothing provides' }],
  };
  expect(compare("p", ruleset, bun)).toBe(
    'p: ident-a@1.0.0 fails analysis in the ruleset (it needs the peer "state", which nothing provides), Bun installs it',
  );
});
