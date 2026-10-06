import { expect, test } from "claude-code/testing";

test("appends the rule as the last session section", async ($, on) => {
  on("prompt.compose", () => ({
    sections: [{ id: "intro", text: "base", scope: "shared" }],
  }));
  const { sections } = await $.prompt.compose({
    model: "claude-opus-5-5",
    promptModel: "claude-opus-5-5",
    surfaces: ["terminal"],
    tools: [],
    outputStyle: null,
    traits: [],
  });
  expect(sections.length).toBe(2);
  expect(sections[1]?.id).toBe("verify-reminder:rule");
  expect(sections[1]?.scope).toBe("session");
  expect(sections[1]?.text).toContain("Before asserting a fact");
});
