import type { Register } from "claude-code";

const RULE =
  `Before asserting a fact about this environment, the code, AI agent tools such as Claude Code, or a specific flag, option, config key, version or default and what it does, check it this turn (file, command output, docs); long-established behavior of mainstream technologies needs no check. If a read, a search, or a tool's public source can settle a question, settle it instead of labeling it unverified; label only what your tools cannot reach. Limit "only", "none" and "all" claims to what you actually read, and copy counts and file:line from this turn's output.`;

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
