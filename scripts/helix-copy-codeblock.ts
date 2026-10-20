export function currentCodeblock(text: string, cursorLine: number): string {
  const lines = text.split(/\r?\n/);
  let opening: { index: number; marker: string } | undefined;
  for (const [index, line] of lines.entries()) {
    if (!opening) {
      const match = line.match(/^\s*(`{3,}|~{3,})(.*)$/);
      if (match && !(match[1][0] === "`" && match[2].includes("`"))) {
        opening = { index, marker: match[1] };
      }
      continue;
    }
    const closing = line.match(/^\s*(`+|~+)\s*$/)?.[1];
    if (
      !closing || closing[0] !== opening.marker[0] ||
      closing.length < opening.marker.length
    ) continue;
    if (opening.index + 1 <= cursorLine && cursorLine <= index + 1) {
      if (index === opening.index + 1) throw new Error("Empty code block");
      return lines.slice(opening.index + 1, index).join("\n");
    }
    opening = undefined;
  }
  if (opening && opening.index + 1 <= cursorLine) {
    throw new Error("Unclosed code block");
  }
  throw new Error("Cursor is outside a code block");
}

if (import.meta.main) {
  try {
    const [line, language, clipboard, ...args] = Deno.args;
    if (language !== "markdown" || !/^[1-9]\d*$/.test(line ?? "")) {
      throw new Error("Expected a Markdown cursor line");
    }
    const text = await new Response(Deno.stdin.readable).text();
    const contents = currentCodeblock(text, Number(line));
    const child = new Deno.Command(clipboard, {
      args,
      stdin: "piped",
      stdout: "null",
      stderr: "null",
    }).spawn();
    const writer = child.stdin.getWriter();
    await writer.write(new TextEncoder().encode(contents));
    await writer.close();
    if (!(await child.status).success) Deno.exit(1);
  } catch {
    // Helix の :pipe-to は stderr のある失敗を出力として扱い、エラーを表示しない。
    Deno.exit(1);
  }
}
