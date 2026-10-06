import type { Register } from "claude-code";

const RULE =
  "Before asserting a fact, check it this turn (file, command output, docs). Label anything unchecked as unverified.";

export const register: Register = (on) => {
  on("prompt.compose", async ($, e, next) => {
    const { sections } = await next(e);
    return {
      sections: [
        ...sections,
        {
          id: `${$.plugin.name}:rule`,
          text: RULE,
          scope: "session",
        },
      ],
    };
  });
};
