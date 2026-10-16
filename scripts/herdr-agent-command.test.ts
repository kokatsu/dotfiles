import {
  AgentCommands,
  CommandError,
  main,
  readPrompt,
} from "./herdr-agent-command.ts";
import fixtures from "./fixtures/herdr-agent-command/claude.json" with {
  type: "json",
};
import codexFixtures from "./fixtures/herdr-agent-command/codex.json" with {
  type: "json",
};

function assert(value: unknown, message = "assertion failed"): asserts value {
  if (!value) throw new Error(message);
}
async function rejects(action: () => Promise<unknown>) {
  try {
    await action();
  } catch (error) {
    assert(error instanceof CommandError);
    return error;
  }
  throw new Error("expected failure");
}
function display(value: string, selected?: string) {
  return `\x1b[0m────────────────────\n❯ ${
    value.replaceAll("\n", "\n  ")
  }\n────────────────────\n${
    selected ? ` ❯ ${selected}  description` : "🤖 Opus 5.5"
  }\n`;
}
const hint = () => display('\x1b[2mTry "fix lint errors"\x1b[22m');
function codexDisplay(value: string, selected?: string) {
  return `\x1b[0m${selected ? `› ${selected}  description\n` : ""}\n› ${
    value.replaceAll("\n", "\n  ")
  }\n\n  GPT-6.1-Sol medium`;
}
const codexHint = () => codexDisplay("\x1b[2mAsk Codex to do anything\x1b[22m");

for (const f of codexFixtures.fixtures) {
  Deno.test(`captured Codex input: ${f.name}`, () => {
    assert(readPrompt(f.ansi, undefined, "codex").kind === f.kind);
    if (f.command) {
      const prompt = readPrompt(f.ansi, f.command, "codex");
      assert(prompt.kind === "draft" && prompt.text === f.command);
    }
  });
}
Deno.test("Codex faint hint, literal hint, blank and unknown displays stay distinct", () => {
  assert(readPrompt(codexHint(), undefined, "codex").kind === "empty");
  assert(
    readPrompt(codexDisplay("Ask Codex to do anything"), undefined, "codex")
      .kind === "draft",
  );
  for (const value of ["", "   "]) {
    assert(
      readPrompt(codexDisplay(value), undefined, "codex").kind === "blank",
    );
  }
  for (
    const value of [
      "\n",
      " \n ",
      "　",
      "[Pasted text #1 +119 lines]",
      "[Image #1]",
      "NORMAL",
      "! shell",
      "\x1b[2mAsk\x1b[22m Codex to do anything",
      "\x1b[8mdraft",
    ]
  ) {
    assert(
      readPrompt(codexDisplay(value), undefined, "codex").kind === "unknown",
      value,
    );
  }
  assert(
    readPrompt(codexHint().replace("GPT-", "Other-"), undefined, "codex")
      .kind === "unknown",
  );
  assert(
    readPrompt(
      codexHint().replace("\x1b[0m", "").replace("\x1b[2m", "").replace(
        "\x1b[22m",
        "",
      ),
      undefined,
      "codex",
    ).kind === "unknown",
  );
});
Deno.test("Codex exact input preserves multiline and rejects mismatched completion", () => {
  const draft = "first\n日本語の下書き\n";
  assert(readPrompt(codexDisplay(draft), undefined, "codex").text === draft);
  assert(
    readPrompt(codexDisplay("/copy", "/clear"), "/copy", "codex").kind ===
      "unknown",
  );
  const fullRow =
    "\x1b[0m          \n› abcdefgh\n          \n  GPT-6.1-Sol medium";
  assert(readPrompt(fullRow, undefined, "codex").kind === "unknown");
});

Deno.test("Codex recognizes the shortcuts hint but refuses other footer panels", () => {
  const help = "\n  ? for shortcuts";
  assert(readPrompt(codexHint() + help, undefined, "codex").kind === "empty");
  assert(
    readPrompt(codexDisplay("draft") + help, undefined, "codex").kind ===
      "draft",
  );
  assert(
    readPrompt(codexDisplay("/copy", "/copy") + help, "/copy", "codex").kind ===
      "draft",
  );
  assert(
    readPrompt(codexDisplay("/cl", "/clear") + help, undefined, "codex")
      .kind === "unknown",
  );
  for (
    const extra of [
      "\n  esc to interrupt",
      "\n  approval required",
      help + help,
      help + "\n  dialog",
    ]
  ) {
    assert(
      readPrompt(codexHint() + extra, undefined, "codex").kind === "unknown",
    );
  }
});

for (const f of fixtures.fixtures) {
  Deno.test(`captured Herdr screen: ${f.name}`, () => {
    assert(readPrompt(f.ansi).kind === f.kind);
    if (f.command) {
      assert(readPrompt(f.ansi, f.command).kind === f.submittedKind);
    }
  });
}
Deno.test("faint placeholder differs from the same literal draft", () => {
  assert(readPrompt(hint()).kind === "empty");
  assert(readPrompt(display('Try "fix lint errors"')).kind === "draft");
  assert(readPrompt(display("\x1b[2munknown hint\x1b[0m")).kind === "unknown");
  assert(
    readPrompt(display('Try "\x1b[2mfix lint errors"')).kind === "unknown",
  );
  assert(
    readPrompt(display("draft").replace("\x1b[0m", "")).kind === "unknown",
  );
});
Deno.test("SGR resets, RGB, indexed colors and OSC links preserve faint state", () => {
  for (
    const value of [
      '\x1b[2m\x1b[0mTry "fix lint errors"',
      '\x1b[2m\x1b[22mTry "fix lint errors"',
      '\x1b[48;2;57;57;71mTry "fix lint errors"',
      '\x1b[38;5;2mTry "fix lint errors"',
    ]
  ) assert(readPrompt(display(value)).kind === "draft");
  assert(
    readPrompt(display('\x1b[2;48;2;57;57;71mTry "fix lint errors"')).kind ===
      "empty",
  );
  assert(
    readPrompt("\x1b]8;;https://example.com\x1b\\" + hint() + "\x1b]8;;\x1b\\")
      .kind === "empty",
  );
});
Deno.test("unknown or incomplete controls never identify an input", () => {
  for (
    const control of [
      "\x1b[",
      "\x1b[48;2;57m",
      "\x1b[?25h",
      "\x1b[8m",
      "\x1b]unknown\x07",
      "\x00",
    ]
  ) assert(readPrompt(display(control + "draft")).kind === "unknown");
});
Deno.test("blank single row is ambiguous; blank multiline and collapsed paste are refused", () => {
  for (const value of ["", "   ", "　"]) {
    assert(readPrompt(display(value)).kind === "blank");
  }
  for (const value of ["\n", "   \n   ", "[Pasted text #1 +119 lines]"]) {
    assert(readPrompt(display(value)).kind === "unknown");
  }
  assert(readPrompt(display("first\n日本語の下書き\nlast")).kind === "draft");
});
Deno.test("completion is refused before clearing and must match submitted command", () => {
  assert(readPrompt(display("/copy", "/copy")).kind === "unknown");
  assert(readPrompt(display("/copy", "/copy"), "/copy").kind === "draft");
  assert(readPrompt(display("/copy", "/clear"), "/copy").kind === "unknown");
  assert(readPrompt(display(" /copy", "/copy"), "/copy").kind === "unknown");
});
Deno.test("attachments, shell, Vim, transcript and missing footer are refused", () => {
  for (
    const screen of [
      "previous output: /copy",
      display("[Image #1]"),
      display("[File name]"),
      "[Attachment #1]\n" + hint(),
      display("! echo unsafe"),
      display("NORMAL"),
      display("draft").replace("🤖 Opus 5.5", "Rewind: choose a message"),
      "────────────────────\n❯ shell\n────────────────────",
    ]
  ) assert(readPrompt(screen).kind === "unknown");
});

async function fixture(
  shared?: { root: string; pane: string; socket?: string },
) {
  const root = shared?.root ?? await Deno.makeTempDir(),
    pane = shared?.pane ?? "p1";
  const env = {
    XDG_RUNTIME_DIR: root,
    TMPDIR: root,
    HERDR_ACTIVE_PANE_ID: pane,
    HERDR_SOCKET_PATH: shared?.socket,
  };
  const calls: string[][] = [], budgets: number[] = [];
  const f = {
    root,
    env,
    calls,
    budgets,
    pane,
    agent: "claude" as string | null,
    session: "s1" as string | null,
    status: "idle",
    process: "claude",
    pid: 200,
    helper: false,
    help: false,
    draft: "first\n日本語の下書き\nlast",
    hinted: false,
    override: undefined as string | undefined,
    stallClear: false,
    enterFails: false,
    bodyFails: false,
    hook: undefined as ((args: string[]) => void | Promise<void>) | undefined,
    inputCalls() {
      return calls.filter((a) => ["send-text", "send-keys"].includes(a[1]));
    },
    entered() {
      return calls.filter((a) => a.at(-1) === "enter").length;
    },
    [Symbol.asyncDispose]: () =>
      shared ? Promise.resolve() : Deno.remove(root, { recursive: true }),
  };
  const run = async (args: string[], budget = 3000): Promise<string> => {
    calls.push(args);
    budgets.push(budget);
    if (f.hook) await f.hook(args);
    if (args[1] === "get") {
      return JSON.stringify({
        result: {
          pane: {
            agent: f.agent,
            agent_status: f.status,
            agent_session: f.session ? { value: f.session } : undefined,
          },
        },
      });
    }
    if (args[1] === "process-info") {
      return JSON.stringify({
        result: {
          process_info: {
            shell_pid: 100,
            foreground_processes: f.process
              ? [
                { name: f.process, pid: f.process === "zsh" ? 100 : f.pid },
                ...(f.helper ? [{ name: "powershell.exe", pid: 300 }] : []),
              ]
              : [],
          },
        },
      });
    }
    if (args[1] === "read") {
      return f.override ??
        (f.agent === "codex"
            ? f.hinted ? codexHint() : codexDisplay(f.draft)
            : f.hinted
            ? hint()
            : display(f.draft)) + (f.help ? "\n  ? for shortcuts" : "");
    }
    if (args[1] === "send-text") {
      f.draft += args[3];
      f.hinted = false;
      if (f.bodyFails) throw new CommandError("ambiguous text delivery");
      return "";
    }
    if (args[1] === "send-keys") {
      if (args.at(-1) === "enter") {
        if (f.enterFails) throw new CommandError("ambiguous delivery");
        if (f.draft === "/exit") f.process = "zsh";
        if (f.draft === "/clear") f.session += "-next";
        f.draft = "";
        f.hinted = f.agent === "codex";
      } else if (!f.stallClear) {
        f.draft = "";
        f.hinted = f.agent === "codex" || args.at(-1) === "esc";
      }
      return "";
    }
    if (args[0] === "notification") return "";
    throw new Error(`unexpected call: ${args.join(" ")}`);
  };
  return Object.assign(f, {
    run,
    controller: (timeout = 800) => new AgentCommands(env, run, timeout),
  });
}

for (const command of ["/copy", "/clear", "/exit"]) {
  Deno.test(`Codex with shortcuts hint sends ${command} once`, async () => {
    await using f = await fixture();
    f.agent = f.process = "codex";
    f.session = null;
    f.help = true;
    f.hinted = true;
    f.draft = "";
    await f.controller().send(command);
    assert(f.entered() === 1 && f.inputCalls().length === 2);
  });
}

for (const command of ["/clear", "/copy", "/exit"]) {
  Deno.test(`replace multiline draft and submit ${command} once`, async () => {
    await using f = await fixture();
    await f.controller().send(command);
    assert(
      JSON.stringify(f.inputCalls()) ===
        JSON.stringify([["agent", "send-keys", "p1", "esc", "esc"], [
          "pane",
          "send-text",
          "p1",
          command,
        ], ["agent", "send-keys", "p1", "enter"]]),
    );
    assert(
      f.calls.filter((a) => a[1] === "read").every((a) => a.includes("--ansi")),
    );
    assert(f.budgets.every((b) => b > 0 && b <= 800));
  });
}
Deno.test("confirmed placeholder skips clear; literal placeholder is cleared", async () => {
  await using f = await fixture();
  f.hinted = true;
  f.draft = "";
  await f.controller().send("/copy");
  assert(f.inputCalls().length === 2);
  f.draft = 'Try "fix lint errors"';
  f.calls.length = 0;
  await f.controller().send("/copy");
  assert(f.inputCalls()[0].at(-1) === "esc");
});
for (const blank of ["", "   ", "　"]) {
  Deno.test(`single-row blank ${JSON.stringify(blank)} uses Ctrl+E Ctrl+U once`, async () => {
    await using f = await fixture();
    f.draft = blank;
    await f.controller().send("/copy");
    assert(
      JSON.stringify(f.inputCalls()[0]) ===
        JSON.stringify(["agent", "send-keys", "p1", "ctrl+e", "ctrl+u"]),
    );
    assert(f.inputCalls().length === 3 && f.entered() === 1);
  });
}
for (const value of ["\n", "   \n   ", "[Pasted text #1 +119 lines]"]) {
  Deno.test(`refuse unsupported draft ${JSON.stringify(value)} without input`, async () => {
    await using f = await fixture();
    f.draft = value;
    await rejects(() => f.controller().send("/copy"));
    assert(f.inputCalls().length === 0);
  });
}
Deno.test("completion before clearing sends no keys", async () => {
  await using f = await fixture();
  f.override = display("/copy", "/copy");
  await rejects(() => f.controller().send("/copy"));
  assert(f.inputCalls().length === 0);
});
for (const status of ["working", "blocked", "unknown"]) {
  Deno.test(`refuse ${status} without input`, async () => {
    await using f = await fixture();
    f.status = status;
    await rejects(() => f.controller().send("/copy"));
    assert(f.inputCalls().length === 0);
  });
}
Deno.test("Codex works without session metadata and permits foreground helpers", async () => {
  await using f = await fixture();
  f.agent = "codex";
  f.session = null;
  f.process = "codex";
  f.helper = true;
  assert(await main(["/copy"], f.env, f.run) === 0);
  assert(f.inputCalls()[0].at(-1) === "ctrl+c");
  assert(f.entered() === 1);
});
for (const command of ["/clear", "/copy", "/exit"]) {
  Deno.test(`Codex without session submits ${command} once and retains its lock`, async () => {
    await using f = await fixture();
    f.agent = f.process = "codex";
    f.session = null;
    let conflicts = 0;
    f.hook = async (args) => {
      if (["send-text", "send-keys"].includes(args[1])) {
        const error = await rejects(() => f.controller().send("/exit"));
        assert(error.message.includes("送信中"));
        conflicts++;
      }
    };
    await f.controller().send(command);
    assert(f.inputCalls()[0].at(-1) === "ctrl+c");
    assert(f.entered() === 1 && conflicts === 3);
    if (command !== "/exit") {
      f.hook = undefined;
      await f.controller().send("/copy");
      assert(f.entered() === 2);
    }
  });
}
Deno.test("Codex known empty skips Ctrl+C and blank uses Ctrl+E Ctrl+U", async () => {
  for (const draft of [null, "", "   ", "Ask Codex to do anything"]) {
    await using f = await fixture();
    f.agent = f.process = "codex";
    f.draft = draft ?? "";
    f.hinted = draft === null;
    await f.controller().send("/copy");
    const first = f.inputCalls()[0];
    if (draft === null) assert(first[1] === "send-text");
    else if (!draft.trim()) {
      assert(first.slice(-2).join(" ") === "ctrl+e ctrl+u");
    } else assert(first.at(-1) === "ctrl+c");
  }
});
for (const status of ["working", "blocked", "unknown"]) {
  Deno.test(`Codex ${status} sends no keys`, async () => {
    await using f = await fixture();
    f.agent = f.process = "codex";
    f.status = status;
    await rejects(() => f.controller().send("/copy"));
    assert(f.inputCalls().length === 0);
  });
}
for (const stage of ["before-clear", "after-clear", "after-body"]) {
  Deno.test(`Codex PID replacement ${stage} is never followed`, async () => {
    await using f = await fixture();
    f.agent = f.process = "codex";
    let reads = 0;
    f.hook = (args) => {
      if (args[1] === "read" && ++reads === 2 && stage === "before-clear") {
        f.pid++;
      }
      if (args.at(-1) === "ctrl+c" && stage === "after-clear") f.pid++;
      if (args[1] === "send-text" && stage === "after-body") f.pid++;
    };
    await rejects(() => f.controller().send("/copy"));
    assert(f.entered() === 0);
    assert(
      f.inputCalls().length ===
        (stage === "before-clear" ? 0 : stage === "after-clear" ? 1 : 2),
    );
  });
}
Deno.test("Codex unknown or completion draft sends no keys", async () => {
  for (
    const screen of [
      codexDisplay("/cl", "/clear"),
      codexDisplay("\n"),
      codexDisplay("　"),
    ]
  ) {
    await using f = await fixture();
    f.agent = f.process = "codex";
    f.override = screen;
    await rejects(() => f.controller().send("/copy"));
    assert(f.inputCalls().length === 0);
  }
});
Deno.test("Codex empty transition immediately before Ctrl+C aborts", async () => {
  await using f = await fixture();
  f.agent = f.process = "codex";
  let reads = 0;
  f.hook = (args) => {
    if (args[1] === "read" && ++reads === 2) f.hinted = true;
  };
  await rejects(() => f.controller().send("/copy"));
  assert(f.inputCalls().length === 0);
});
Deno.test("Codex ambiguous blank after clearing never receives command text", async () => {
  await using f = await fixture();
  f.agent = f.process = "codex";
  let reads = 0;
  f.hook = (args) => {
    if (args[1] === "read" && ++reads === 4) f.override = codexDisplay("");
  };
  await rejects(() => f.controller().send("/copy"));
  assert(f.inputCalls().length === 1 && f.inputCalls()[0].at(-1) === "ctrl+c");
});
Deno.test("Codex clear waits through working and pending command, without session IDs", async () => {
  await using f = await fixture();
  f.agent = f.process = "codex";
  f.session = null;
  let submitted = false, gets = 0;
  f.hook = async (args) => {
    if (args.at(-1) === "enter") submitted = true;
    if (submitted && args[1] === "get") {
      const error = await rejects(() => f.controller().send("/copy"));
      assert(error.message.includes("送信中"));
      f.session = null;
      f.status = ++gets < 3 ? "working" : "idle";
      f.override = gets < 5 ? codexDisplay("/clear", "/clear") : undefined;
    }
  };
  await f.controller().send("/clear");
  assert(gets >= 5 && f.session === null && f.entered() === 1);
});
Deno.test("Codex post-Enter PID change and blank return never count as success", async () => {
  for (const mismatch of ["pid", "blank"]) {
    await using f = await fixture();
    f.agent = f.process = "codex";
    f.hook = (args) => {
      if (args.at(-1) === "enter") {
        if (mismatch === "pid") f.pid++;
        else f.override = codexDisplay("");
      }
    };
    const error = await rejects(() => f.controller(100).send("/clear"));
    assert(error.message.includes("実行済みの可能性") && f.entered() === 1);
  }
});
Deno.test("refuse absent agent, missing session, foreground changes and command injection", async () => {
  await using f = await fixture();
  f.agent = null;
  await rejects(() => f.controller().send("/copy"));
  f.agent = "claude";
  f.session = null;
  await rejects(() => f.controller().send("/copy"));
  f.session = "s1";
  f.process = "nvim";
  await rejects(() => f.controller().send("/copy"));
  await rejects(() => f.controller().send("/copy\n/exit"));
  assert(f.inputCalls().length === 0);
});
Deno.test("changed draft classification immediately before clear aborts", async () => {
  await using f = await fixture();
  let reads = 0;
  f.hook = (args) => {
    if (args[1] === "read" && ++reads === 2) f.hinted = true;
  };
  await rejects(() => f.controller().send("/copy"));
  assert(f.inputCalls().length === 0);
});
Deno.test("session replacement after clear never sends body or Enter", async () => {
  await using f = await fixture();
  f.hook = (args) => {
    if (args.at(-1) === "esc") f.session = "s2";
  };
  await rejects(() => f.controller().send("/copy"));
  assert(f.inputCalls().length === 1);
});
Deno.test("foreground change after body never submits", async () => {
  await using f = await fixture();
  f.hook = (args) => {
    if (args[1] === "send-text") f.process = "nvim";
  };
  await rejects(() => f.controller().send("/copy"));
  assert(f.entered() === 0);
});
Deno.test("lock survives Enter until the pending command disappears", async () => {
  await using f = await fixture();
  let submitted = false, reads = 0;
  f.hook = async (args) => {
    if (args.at(-1) === "enter") {
      submitted = true;
      f.override = display("/copy", "/copy");
    } else if (submitted && args[1] === "read") {
      const error = await rejects(() => f.controller().send("/copy"));
      assert(error.message.includes("送信中"));
      if (++reads === 3) f.override = undefined;
    }
  };
  await f.controller().send("/copy");
  assert(
    reads === 3,
    "sender returned before the previous command disappeared",
  );
  assert(f.entered() === 1);
  f.hook = undefined;
  await f.controller().send("/copy");
  assert(f.entered() === 2);
});
Deno.test("unconfirmed post-Enter screen times out without another Enter", async () => {
  await using f = await fixture();
  f.hook = (args) => {
    if (args.at(-1) === "enter") f.override = display("/copy", "/copy");
  };
  const error = await rejects(() => f.controller(60).send("/copy"));
  assert(error.message.includes("実行済みの可能性"));
  assert(f.entered() === 1);
});
Deno.test("clear holds its lock through the old idle screen and working hook until the new idle session", async () => {
  await using f = await fixture();
  let submitted = false, reads = 0;
  f.hook = async (args) => {
    if (args.at(-1) === "enter") submitted = true;
    if (submitted && args[1] === "get") {
      const error = await rejects(() => f.controller().send("/copy"));
      assert(error.message.includes("送信中"));
      reads++;
      f.status = reads === 2 || reads === 3 ? "working" : "idle";
      f.session = reads < 4 ? "s1" : "s2";
    }
  };
  await f.controller().send("/clear");
  assert(reads >= 4 && f.session === "s2" && f.status === "idle");
  assert(f.entered() === 1 && f.inputCalls().length === 3);
});
Deno.test("clear hook that remains working times out without more input", async () => {
  await using f = await fixture();
  f.hook = (args) => {
    if (args.at(-1) === "enter") f.status = "working";
  };
  const start = performance.now();
  const error = await rejects(() => f.controller(100).send("/clear"));
  assert(
    performance.now() - start >= 100,
    "working hook was rejected before the deadline",
  );
  assert(error.message.includes("実行済みの可能性"));
  assert(f.entered() === 1 && f.inputCalls().length === 3);
});
Deno.test("exit waits for the original shell instead of trusting the old screen", async () => {
  await using f = await fixture();
  let submitted = false, processReads = 0;
  f.hook = (args) => {
    if (args.at(-1) === "enter") submitted = true;
    if (submitted && args[1] === "process-info") {
      f.process = ++processReads < 3 ? "claude" : "zsh";
    }
  };
  await f.controller().send("/exit");
  assert(processReads === 3 && f.entered() === 1);
});
Deno.test("session replacement after copy Enter is not followed", async () => {
  await using f = await fixture();
  f.hook = (args) => {
    if (args.at(-1) === "enter") f.session = "other";
  };
  const error = await rejects(() => f.controller().send("/copy"));
  assert(error.message.includes("実行済みの可能性"));
  assert(f.entered() === 1);
});
Deno.test("clear timeout is never retried and sends no body", async () => {
  await using f = await fixture();
  f.stallClear = true;
  await rejects(() => f.controller(60).send("/copy"));
  assert(f.inputCalls().length === 1);
});
Deno.test("body mismatch, leading leftovers and wrong completion never submit", async () => {
  for (
    const override of [
      display(" /copy"),
      display("/copy", "/clear"),
      "response contains /copy",
    ]
  ) {
    await using f = await fixture();
    f.hook = (args) => {
      if (args[1] === "send-text") f.override = override;
    };
    await rejects(() => f.controller(60).send("/copy"));
    assert(f.entered() === 0);
    assert(f.inputCalls().filter((a) => a[1] === "send-text").length === 1);
  }
});
Deno.test("matching completion after body is accepted", async () => {
  await using f = await fixture();
  f.hook = (args) => {
    if (args[1] === "send-text") f.override = display("/copy", "/copy");
    if (args.at(-1) === "enter") f.override = undefined;
  };
  await f.controller().send("/copy");
  assert(f.entered() === 1);
});
Deno.test("ambiguous text and Enter failures are never retried", async () => {
  await using f = await fixture();
  f.bodyFails = true;
  await rejects(() => f.controller().send("/copy"));
  assert(
    f.entered() === 0 &&
      f.inputCalls().filter((a) => a[1] === "send-text").length === 1,
  );
  f.bodyFails = false;
  f.draft = "draft";
  f.enterFails = true;
  f.calls.length = 0;
  const error = await rejects(() => f.controller().send("/copy"));
  assert(error.message.includes("実行済みの可能性") && f.entered() === 1);
});
Deno.test("lock lasts through clear, body and Enter, then releases immediately", async () => {
  await using f = await fixture();
  let rejections = 0;
  f.hook = async (args) => {
    if (["send-text", "send-keys"].includes(args[1])) {
      const error = await rejects(() => f.controller().send("/exit"));
      assert(error.message.includes("送信中"));
      rejections++;
    }
  };
  await f.controller().send("/copy");
  assert(rejections === 3 && f.entered() === 1);
  f.hook = undefined;
  await f.controller().send("/clear");
  assert(f.entered() === 2);
});
Deno.test("failure releases the lock for the next operation", async () => {
  await using f = await fixture();
  f.enterFails = true;
  await rejects(() => f.controller().send("/copy"));
  f.enterFails = false;
  f.draft = "draft";
  await f.controller().send("/copy");
  assert(f.entered() === 2);
});
Deno.test("different panes and different sockets do not share locks", async () => {
  await using first = await fixture();
  await using second = await fixture({ root: first.root, pane: "p2" });
  await using third = await fixture({
    root: first.root,
    pane: "p1",
    socket: "/other.sock",
  });
  first.hook = async (args) => {
    if (args[1] === "send-text") {
      await Promise.all([
        second.controller().send("/copy"),
        third.controller().send("/exit"),
      ]);
    }
  };
  await first.controller().send("/clear");
  assert(
    first.entered() === 1 && second.entered() === 1 && third.entered() === 1,
  );
});
Deno.test("whole deadline limits a single slow Herdr call", async () => {
  await using f = await fixture();
  f.hook = async (args) => {
    if (args.at(-1) === "esc") {
      await new Promise((resolve) => setTimeout(resolve, 30));
    }
  };
  await rejects(() => f.controller(20).send("/copy"));
  assert(f.inputCalls().length === 1);
});
Deno.test("invalid pane and unavailable runtime directory send no input", async () => {
  await using f = await fixture();
  await rejects(() =>
    new AgentCommands({ ...f.env, HERDR_ACTIVE_PANE_ID: "../p1" }, f.run).send(
      "/copy",
    )
  );
  await rejects(() =>
    new AgentCommands({ HERDR_ACTIVE_PANE_ID: "p1" }, f.run).send("/copy")
  );
  assert(f.inputCalls().length === 0);
});
