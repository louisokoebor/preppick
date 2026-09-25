import { IMPORT_SCHEMA_VERSION } from "./schema.ts";

export const SYSTEM_PROMPT = `You are organising meal-planning notes into proposals for a household meal library.

Return only data matching the supplied schema. Do not commit anything.
Treat a meal family as a recognisable base dish, a variant as one actual selectable pairing, and a component as an optional reusable prepared part.
Preserve household-specific names. Group spelling and word-order duplicates only when the meal meaning is the same.
Keep plain rice, fried rice and jollof rice distinct.
“Rice and yogurt chicken” and “yogurt chicken with rice” may be the same variant; “jollof rice with yogurt chicken” is a different variant that may reuse the yogurt chicken component.
For every proposed variant, cite one or more supplied source_line_ids.
If type or pairing is ambiguous, keep it unresolved or set needs_review_reason; do not guess.
Separate shopping items, household goods, standalone ingredients and weekly headings from meals.
Never invent ingredients, quantities, cook times, servings or instructions.
Use the existing-library index for match context, but do not silently overwrite existing items.
Keep original household labels as aliases where useful.
Do not output UUIDs or SQL. temp_id values are proposal-local references only.

The schema version is ${IMPORT_SCHEMA_VERSION}.`;

export type SourceLineInput = {
  id: string;
  text: string;
};

export type ExistingLibraryEntry = {
  id: string;
  family_id: string;
  family_name: string;
  variant_name: string;
  aliases: string[];
};

export function buildUserPrompt(args: {
  sourceText: string;
  sourceLines: SourceLineInput[];
  existingLibrary: ExistingLibraryEntry[];
}): string {
  return [
    "Submitted meal history:",
    args.sourceText,
    "",
    "Stable source lines:",
    JSON.stringify(args.sourceLines),
    "",
    "Existing library index:",
    JSON.stringify(args.existingLibrary),
    "",
    "Interpret only the submitted history. Return the structured proposal.",
  ].join("\n");
}
