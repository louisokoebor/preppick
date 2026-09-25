import type { MealImportProposal } from "./schema.ts";

export class ImportValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ImportValidationError";
  }
}

function requireRecord(value: unknown, label: string): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new ImportValidationError(`${label} must be an object`);
  }
  return value as Record<string, unknown>;
}

function requireString(value: unknown, label: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new ImportValidationError(`${label} must be a non-empty string`);
  }
  return value.trim();
}

function requireStringArray(value: unknown, label: string): string[] {
  if (!Array.isArray(value)) {
    throw new ImportValidationError(`${label} must be an array`);
  }
  return value.map((item, index) => requireString(item, `${label}[${index}]`));
}

function requireKeys(
  value: Record<string, unknown>,
  required: string[],
  allowed: string[],
  label: string,
): void {
  for (const key of required) {
    if (!(key in value)) {
      throw new ImportValidationError(`${label}.${key} is required`);
    }
  }
  for (const key of Object.keys(value)) {
    if (!allowed.includes(key)) {
      throw new ImportValidationError(`${label}.${key} is not supported`);
    }
  }
}

function assertProposalTempId(value: string, label: string): void {
  if (!/^(family|variant)_[A-Za-z0-9_-]+$/.test(value)) {
    throw new ImportValidationError(`${label} must be a proposal-local temp_id`);
  }
}

function assertSourceLineIds(
  value: unknown,
  label: string,
  submittedIds: Set<string>,
): string[] {
  const ids = requireStringArray(value, label);
  if (ids.length === 0) {
    throw new ImportValidationError(`${label} must contain at least one ID`);
  }
  for (const id of ids) {
    if (!submittedIds.has(id)) {
      throw new ImportValidationError(`${label} references an unknown source line`);
    }
  }
  return [...new Set(ids)];
}

export function validateProposal(
  value: unknown,
  submittedSourceLineIds: string[],
): MealImportProposal {
  const root = requireRecord(value, "proposal");
  requireKeys(
    root,
    ["schema_version", "families", "unresolved"],
    ["schema_version", "families", "unresolved"],
    "proposal",
  );
  if (root.schema_version !== "1") {
    throw new ImportValidationError("Unsupported proposal schema version");
  }
  if (!Array.isArray(root.families) || !Array.isArray(root.unresolved)) {
    throw new ImportValidationError("families and unresolved must be arrays");
  }

  const submittedIds = new Set(submittedSourceLineIds);
  const familyIds = new Set<string>();
  const variantIds = new Set<string>();
  const families: MealImportProposal["families"] = [];

  for (let familyIndex = 0; familyIndex < root.families.length; familyIndex++) {
    const family = requireRecord(root.families[familyIndex], `families[${familyIndex}]`);
    requireKeys(
      family,
      ["temp_id", "preferred_name", "aliases", "variants"],
      ["temp_id", "preferred_name", "aliases", "variants"],
      `families[${familyIndex}]`,
    );
    const familyId = requireString(family.temp_id, `families[${familyIndex}].temp_id`);
    assertProposalTempId(familyId, `families[${familyIndex}].temp_id`);
    if (!familyId.startsWith("family_") || familyIds.has(familyId)) {
      throw new ImportValidationError("Family temp_ids must be unique family_ references");
    }
    familyIds.add(familyId);
    const aliases = requireStringArray(family.aliases, `families[${familyIndex}].aliases`);
    if (!Array.isArray(family.variants)) {
      throw new ImportValidationError(`families[${familyIndex}].variants must be an array`);
    }

    const variants: MealImportProposal["families"][number]["variants"] = [];
    for (let variantIndex = 0; variantIndex < family.variants.length; variantIndex++) {
      const variant = requireRecord(
        family.variants[variantIndex],
        `families[${familyIndex}].variants[${variantIndex}]`,
      );
      const label = `families[${familyIndex}].variants[${variantIndex}]`;
      requireKeys(
        variant,
        [
          "temp_id",
          "display_name",
          "component_names",
          "meal_slot",
          "source_line_ids",
          "confidence_band",
          "needs_review_reason",
        ],
        [
          "temp_id",
          "display_name",
          "component_names",
          "meal_slot",
          "source_line_ids",
          "confidence_band",
          "needs_review_reason",
        ],
        label,
      );
      const variantId = requireString(variant.temp_id, `${label}.temp_id`);
      assertProposalTempId(variantId, `${label}.temp_id`);
      if (!variantId.startsWith("variant_") || variantIds.has(variantId)) {
        throw new ImportValidationError("Variant temp_ids must be unique variant_ references");
      }
      variantIds.add(variantId);
      const mealSlot = variant.meal_slot;
      if (
        mealSlot !== null &&
        mealSlot !== "breakfast" &&
        mealSlot !== "lunch" &&
        mealSlot !== "dinner"
      ) {
        throw new ImportValidationError(`${label}.meal_slot is invalid`);
      }
      const confidence = variant.confidence_band;
      if (confidence !== "high" && confidence !== "medium" && confidence !== "low") {
        throw new ImportValidationError(`${label}.confidence_band is invalid`);
      }
      const reviewReason = variant.needs_review_reason;
      if (reviewReason !== null) requireString(reviewReason, `${label}.needs_review_reason`);
      variants.push({
        temp_id: variantId,
        display_name: requireString(variant.display_name, `${label}.display_name`),
        component_names: requireStringArray(variant.component_names, `${label}.component_names`),
        meal_slot: mealSlot as "breakfast" | "lunch" | "dinner" | null,
        source_line_ids: assertSourceLineIds(
          variant.source_line_ids,
          `${label}.source_line_ids`,
          submittedIds,
        ),
        confidence_band: confidence,
        needs_review_reason: reviewReason === null
          ? null
          : reviewReason.trim(),
      });
    }
    families.push({
      temp_id: familyId,
      preferred_name: requireString(
        family.preferred_name,
        `families[${familyIndex}].preferred_name`,
      ),
      aliases,
      variants,
    });
  }

  const unresolved: MealImportProposal["unresolved"] = [];
  for (let index = 0; index < root.unresolved.length; index++) {
    const item = requireRecord(root.unresolved[index], `unresolved[${index}]`);
    const label = `unresolved[${index}]`;
    requireKeys(
      item,
      ["source_line_ids", "original_text", "reason"],
      ["source_line_ids", "original_text", "reason"],
      label,
    );
    unresolved.push({
      source_line_ids: assertSourceLineIds(item.source_line_ids, `${label}.source_line_ids`, submittedIds),
      original_text: requireString(item.original_text, `${label}.original_text`),
      reason: requireString(item.reason, `${label}.reason`),
    });
  }

  return {
    schema_version: "1",
    families,
    unresolved,
  };
}
