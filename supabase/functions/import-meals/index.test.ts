import { assertEquals, assertThrows } from "https://deno.land/std@0.224.0/assert/mod.ts";
import { validateProposal } from "./validate.ts";

const fixtures = JSON.parse(
  await Deno.readTextFile(new URL("./fixtures/meal-import-cases.json", import.meta.url)),
);

Deno.test("valid meal import fixture preserves source evidence", () => {
  const proposal = validateProposal(
    fixtures.valid.proposal,
    fixtures.valid.source_line_ids,
  );
  assertEquals(proposal.families.length, 3);
  assertEquals(proposal.families[0].variants[0].source_line_ids, ["line_1", "line_2"]);
  assertEquals(proposal.unresolved[0].source_line_ids, ["line_5"]);
});

Deno.test("unknown source IDs are rejected", () => {
  assertThrows(() =>
    validateProposal(
      fixtures.invalid_source_line.proposal,
      fixtures.invalid_source_line.source_line_ids,
    )
  );
});
