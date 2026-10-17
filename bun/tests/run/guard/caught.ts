// Catches the guard's error for an undeclared import: a documented limitation,
// the run does not fail (R13, R14).
try {
  await import("./stale.ts");
} catch {}
console.log("caught");
