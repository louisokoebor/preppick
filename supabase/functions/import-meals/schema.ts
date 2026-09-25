export const IMPORT_SCHEMA_VERSION = "1";

export const mealImportSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    schema_version: { type: "string" },
    families: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          temp_id: { type: "string" },
          preferred_name: { type: "string" },
          aliases: { type: "array", items: { type: "string" } },
          variants: {
            type: "array",
            items: {
              type: "object",
              additionalProperties: false,
              properties: {
                temp_id: { type: "string" },
                display_name: { type: "string" },
                component_names: {
                  type: "array",
                  items: { type: "string" },
                },
                meal_slot: {
                  type: ["string", "null"],
                  enum: ["breakfast", "lunch", "dinner", null],
                },
                source_line_ids: {
                  type: "array",
                  items: { type: "string" },
                },
                confidence_band: {
                  type: "string",
                  enum: ["high", "medium", "low"],
                },
                needs_review_reason: {
                  type: ["string", "null"],
                },
              },
              required: [
                "temp_id",
                "display_name",
                "component_names",
                "meal_slot",
                "source_line_ids",
                "confidence_band",
                "needs_review_reason",
              ],
            },
          },
        },
        required: ["temp_id", "preferred_name", "aliases", "variants"],
      },
    },
    unresolved: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          source_line_ids: {
            type: "array",
            items: { type: "string" },
          },
          original_text: { type: "string" },
          reason: { type: "string" },
        },
        required: ["source_line_ids", "original_text", "reason"],
      },
    },
  },
  required: ["schema_version", "families", "unresolved"],
} as const;

export type MealImportProposal = {
  schema_version: string;
  families: Array<{
    temp_id: string;
    preferred_name: string;
    aliases: string[];
    variants: Array<{
      temp_id: string;
      display_name: string;
      component_names: string[];
      meal_slot: "breakfast" | "lunch" | "dinner" | null;
      source_line_ids: string[];
      confidence_band: "high" | "medium" | "low";
      needs_review_reason: string | null;
    }>;
  }>;
  unresolved: Array<{
    source_line_ids: string[];
    original_text: string;
    reason: string;
  }>;
};
