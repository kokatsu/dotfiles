#!/usr/bin/env -S deno run --allow-read=${CLAUDE_CONFIG_DIR},./.claude --allow-write=./.claude --allow-run=claude --allow-env

interface HookInput {
  session_id: string;
  transcript_path: string;
  cwd: string;
  permission_mode: string;
  hook_event_name: string;
  reason: string;
}

interface TranscriptEntry {
  type:
    | "user"
    | "assistant"
    | "file-history-snapshot"
    | "progress"
    | "system"
    | "summary";
  timestamp?: string;
  message?: {
    role: string;
    content: string | ContentItem[];
  };
}

interface TextContent {
  type: "text";
  text: string;
}

interface ToolUseContent {
  type: "tool_use";
  name: string;
  input: Record<string, unknown>;
}

type ContentItem = TextContent | ToolUseContent | { type: string };

async function main() {
  const decoder = new TextDecoder();
  const chunks: Uint8Array[] = [];
  for await (const chunk of Deno.stdin.readable) {
    chunks.push(chunk);
  }
  const totalLength = chunks.reduce((sum, c) => sum + c.length, 0);
  const merged = new Uint8Array(totalLength);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.length;
  }

  let input: HookInput;
  try {
    input = JSON.parse(decoder.decode(merged));
  } catch {
    console.error("Failed to parse hook input");
    Deno.exitCode = 1;
    return;
  }

  const { transcript_path, cwd } = input;

  if (!transcript_path) {
    return;
  }

  // トランスクリプトから会話を抽出
  const conversationText = await extractConversation(transcript_path, cwd);
  if (!conversationText) {
    console.log("Handover skipped: no conversation content");
    return;
  }

  // claude -p でサマリー生成
  const summary = await generateSummary(conversationText);
  if (!summary) {
    console.error("Failed to generate handover summary");
    Deno.exitCode = 1;
    return;
  }

  // HANDOVER ファイルを保存
  const dateStr = new Date().toISOString().split("T")[0];
  const handoverDir = `${cwd}/.claude`;
  await Deno.mkdir(handoverDir, { recursive: true });

  const handoverPath = `${handoverDir}/HANDOVER-${dateStr}.md`;

  // 既存ファイルがあれば追記、なければ新規作成
  try {
    await Deno.stat(handoverPath);
    await Deno.writeTextFile(handoverPath, `\n---\n\n${summary}\n`, {
      append: true,
    });
  } catch {
    await Deno.writeTextFile(handoverPath, `${summary}\n`);
  }

  console.log(`Handover saved: ${handoverPath}`);
}

async function extractConversation(
  transcriptPath: string,
  cwd: string,
): Promise<string | null> {
  try {
    const content = await Deno.readTextFile(transcriptPath);
    const lines = content.trim().split("\n");
    const parts: string[] = [];
    const filesChanged = new Set<string>();
    const commands: string[] = [];

    for (const line of lines) {
      if (!line.trim()) continue;
      try {
        const entry: TranscriptEntry = JSON.parse(line);

        if (entry.type === "user" && entry.message?.role === "user") {
          const text = extractText(entry.message.content);
          if (text) {
            parts.push(`[User]: ${text}`);
          }
        }

        if (entry.type === "assistant" && entry.message?.role === "assistant") {
          const contentArray = entry.message.content;
          if (Array.isArray(contentArray)) {
            for (const item of contentArray) {
              if (item.type === "text") {
                const t = (item as TextContent).text;
                if (t) parts.push(`[Assistant]: ${t}`);
              }
              if (item.type === "tool_use") {
                const tool = item as ToolUseContent;
                if (
                  tool.name === "Write" || tool.name === "Edit" ||
                  tool.name === "NotebookEdit"
                ) {
                  const path = (tool.input.file_path ||
                    tool.input.notebook_path) as string;
                  if (path) filesChanged.add(toRelative(path, cwd));
                }
                if (tool.name === "Bash") {
                  const cmd = tool.input.command as string;
                  if (cmd) commands.push(cmd.split("\n")[0]);
                }
              }
            }
          }
        }
      } catch {
        // skip
      }
    }

    if (parts.length === 0) return null;

    // コンテキストを組み立て（最大50000文字）
    let result = parts.join("\n\n");
    if (filesChanged.size > 0) {
      result += `\n\n[Changed files]: ${[...filesChanged].join(", ")}`;
    }
    if (commands.length > 0) {
      const uniqueCmds = [...new Set(commands)].slice(0, 20);
      result += `\n\n[Commands]: ${uniqueCmds.join("; ")}`;
    }

    if (result.length > 50000) {
      result = `${result.slice(0, 50000)}\n\n... (truncated)`;
    }

    return result;
  } catch {
    return null;
  }
}

function extractText(content: string | ContentItem[]): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .filter((c): c is TextContent => c.type === "text" && "text" in c)
      .map((c) => c.text)
      .join("\n");
  }
  return "";
}

function toRelative(filePath: string, cwd: string): string {
  if (filePath.startsWith(`${cwd}/`)) {
    return filePath.slice(cwd.length + 1);
  }
  return filePath;
}

async function generateSummary(
  conversationText: string,
): Promise<string | null> {
  const prompt = `以下はClaude Codeのセッショントランスクリプトです。
次のセッションに引き継ぐための簡潔なハンドオーバー文書を日本語で作成してください。

フォーマット:
# Handover

## 完了タスク
- 完了した作業を箇条書き

## 現在の状態
- コードベースの現在の状態、変更されたファイル

## 未完了・次のステップ
- まだ終わっていない作業や、次にやるべきこと

## 重要な決定事項
- セッション中に行われた技術的な意思決定

## 注意事項
- 既知の問題、ワークアラウンド、注意点

不要なセクションは省略してください。簡潔に記述してください。

---
${conversationText}`;

  try {
    const proc = new Deno.Command("claude", {
      args: ["-p", prompt, "--model", "haiku"],
      stdout: "piped",
      stderr: "piped",
    });

    const output = await proc.output();
    if (!output.success) {
      const stderr = new TextDecoder().decode(output.stderr);
      console.error(`claude -p failed: ${stderr}`);
      return null;
    }

    return new TextDecoder().decode(output.stdout).trim();
  } catch (e) {
    console.error(`Failed to run claude: ${e}`);
    return null;
  }
}

main();
