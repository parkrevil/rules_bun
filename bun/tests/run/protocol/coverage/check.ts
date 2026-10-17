// Checks the merged coverage report of quickstart 6. Run as:
//   bazel coverage --combined_report=lcov //bun/tests/run/protocol/coverage:coverage_test
//   bazel run //bun/tests/run/protocol/coverage:coverage_check -- bazel-out/_coverage/_coverage_report.dat
// Bazel adds a baseline record without line data for every instrumented file, so
// the record must also count an executed line.

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const expected = "SF:bun/tests/run/protocol/coverage/covered.ts";
const report = resolve(process.env.BUILD_WORKING_DIRECTORY ?? "", process.argv[2] ?? "");
const records = readFileSync(report, "utf8")
  .split("end_of_record")
  .map((record) => record.trim().split("\n"));
const covered = records.some(
  (lines) => lines.includes(expected) && lines.some((line) => /^DA:\d+,[1-9]\d*/.test(line)),
);
if (!covered) {
  console.error(
    `${report} holds no record ${expected} with an executed line; ` +
      "check the bunlcov_<uuid>.dat file and the SF: rewrite (G7)",
  );
  process.exit(1);
}
