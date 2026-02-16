#!/usr/bin/env -S deno run --allow-read=${CLAUDE_CONFIG_DIR},./.claude --allow-write=./.claude/session-logs --allow-env

interface HookInput {
  session_id: string;
  transcript_path: string;
  cwd: string;
  permission_mode: string;
  hook_event_name: string;
  reason: string;
}

interface ToolUseContent {
  type: "tool_use";
  id: string;
  name: string;
  input: Record<string, unknown>;
}

interface TextContent {
  type: "text";
  text: string;
}

interface ThinkingContent {
  type: "thinking";
  thinking: string;
}

interface ToolResultContent {
  type: "tool_result";
  tool_use_id: string;
  content?: string | Array<{ type: string; text?: string }>;
}

type ContentItem =
  | ToolUseContent
  | TextContent
  | ThinkingContent
  | ToolResultContent
  | { type: string };

interface TranscriptEntry {
  type:
    | "user"
    | "assistant"
    | "file-history-snapshot"
    | "progress"
    | "system"
    | "summary";
  sessionId?: string;
  gitBranch?: string;
  timestamp?: string;
  isSidechain?: boolean;
  message?: {
    role: string;
    content: string | ContentItem[];
    usage?: {
      input_tokens: number;
      output_tokens: number;
      cache_creation_input_tokens?: number;
      cache_read_input_tokens?: number;
    };
  };
}

interface FileChange {
  path: string;
  operation: string;
  count: number;
}

interface InvestigationEntry {
  type: "Read" | "Grep" | "Glob";
  target: string;
}

interface SkillEntry {
  name: string;
  args?: string;
}

interface AgentEntry {
  subagentType: string;
  description: string;
}

type ActivityTag =
  | "PR作成"
  | "PRレビュー"
  | "実装"
  | "調査"
  | "デバッグ"
  | "git操作"
  | "設計";

interface TokenUsage {
  inputTokens: number;
  outputTokens: number;
  cacheTokens: number;
}

interface SessionSummary {
  userMessages: Array<{ timestamp?: string; text: string }>;
  assistantFinalResponse: string;
  filesChanged: Map<string, FileChange>;
  bashCommands: string[];
  investigations: InvestigationEntry[];
  skills: SkillEntry[];
  agents: AgentEntry[];
  outcomes: string[];
  activityTags: ActivityTag[];
  tokenUsage: TokenUsage;
  gitBranch: string;
  startTime: string | null;
  endTime: string | null;
}

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
  const inputText = decoder.decode(merged);

  let input: HookInput;
  try {
    input = JSON.parse(inputText);
  } catch {
    console.error("Failed to parse hook input");
    Deno.exitCode = 1;
    return;
  }

  const { session_id, transcript_path, cwd, reason } = input;

  if (!session_id || !transcript_path) {
    return;
  }

  // トランスクリプトを解析
  const summary = await analyzeTranscript(transcript_path, cwd);

  // 空セッションはスキップ
  if (
    summary.userMessages.length === 0 && summary.filesChanged.size === 0 &&
    summary.bashCommands.length === 0
  ) {
    console.log(`Session skipped (empty): ${session_id}`);
    return;
  }

  // 月単位ディレクトリを作成 (YYYY-MM) — トランスクリプト基準の日付を使用
  const refTime = summary.endTime ?? summary.startTime;
  const refDate = refTime ? new Date(refTime) : new Date();
  const monthStr = refDate.toISOString().slice(0, 7);
  const dateStr = refDate.toISOString().split("T")[0];
  const logDir = `${cwd}/.claude/session-logs/${monthStr}`;
  await Deno.mkdir(logDir, { recursive: true });

  // 日付ファイルパス
  const logFile = `${logDir}/${dateStr}.md`;

  // 重複セッション防止: 同一セッションIDが既存ファイルに存在するかチェック
  const shortId = session_id.slice(0, 8);
  try {
    const existingContent = await Deno.readTextFile(logFile);
    if (existingContent.includes(`## セッション: ${shortId}`)) {
      console.log(`Session already logged (duplicate): ${session_id}`);
      return;
    }
  } catch {
    // ファイルが存在しない場合は新規作成なのでOK
  }

  // Markdown生成
  const markdown = generateMarkdown({
    sessionId: session_id,
    reason,
    summary,
  });

  // 日付ファイルに追記
  await Deno.writeTextFile(logFile, markdown, { append: true });

  console.log(`Session logged: ${session_id} -> ${logFile}`);
}

async function analyzeTranscript(
  transcriptPath: string,
  cwd: string,
): Promise<SessionSummary> {
  const summary: SessionSummary = {
    userMessages: [],
    assistantFinalResponse: "",
    filesChanged: new Map(),
    bashCommands: [],
    investigations: [],
    skills: [],
    agents: [],
    outcomes: [],
    activityTags: [],
    tokenUsage: { inputTokens: 0, outputTokens: 0, cacheTokens: 0 },
    gitBranch: "unknown",
    startTime: null,
    endTime: null,
  };

  try {
    const content = await Deno.readTextFile(transcriptPath);
    const lines = content.trim().split("\n");

    for (const line of lines) {
      if (!line.trim()) continue;

      try {
        const entry: TranscriptEntry = JSON.parse(line);

        // タイムスタンプの追跡（最初と最後）
        if (entry.timestamp) {
          if (!summary.startTime) summary.startTime = entry.timestamp;
          summary.endTime = entry.timestamp;
        }

        // ブランチ名の取得（最初のエントリから）
        if (entry.gitBranch && summary.gitBranch === "unknown") {
          summary.gitBranch = entry.gitBranch;
        }

        // ユーザーメッセージを抽出（Phase 1.1: type === "user" に修正）
        if (entry.type === "user" && entry.message?.role === "user") {
          const text = extractUserText(entry.message.content);
          if (text) {
            summary.userMessages.push({ timestamp: entry.timestamp, text });
          }
        }

        // アシスタントメッセージからツール使用と最終回答を抽出
        if (entry.type === "assistant" && entry.message?.role === "assistant") {
          // トークン使用量の累計
          const usage = entry.message.usage;
          if (usage) {
            summary.tokenUsage.inputTokens += usage.input_tokens || 0;
            summary.tokenUsage.outputTokens += usage.output_tokens || 0;
            summary.tokenUsage.cacheTokens +=
              (usage.cache_creation_input_tokens || 0) +
              (usage.cache_read_input_tokens || 0);
          }

          const contentArray = entry.message.content;
          if (Array.isArray(contentArray)) {
            for (const item of contentArray) {
              if (item.type === "tool_use") {
                const toolUse = item as ToolUseContent;
                processToolUse(toolUse, summary, cwd);
              }

              // テキスト回答を抽出（最後のものを最終回答として保持）
              if (item.type === "text") {
                const textContent = item as TextContent;
                if (textContent.text) {
                  summary.assistantFinalResponse = textContent.text;
                }
              }
            }
          }
        }
      } catch {
        // 行のパースエラーは無視
      }
    }
  } catch {
    // ファイル読み込みエラーは無視
  }

  // Bashコマンドから成果物を抽出
  extractOutcomes(summary);

  // 活動タグの自動判定
  summary.activityTags = detectActivityTags(summary);

  return summary;
}

function processToolUse(
  toolUse: ToolUseContent,
  summary: SessionSummary,
  cwd: string,
): void {
  const { name, input } = toolUse;

  // Write/Edit/NotebookEdit → ファイル変更を記録
  if (name === "Write" || name === "Edit" || name === "NotebookEdit") {
    const filePath = (name === "NotebookEdit"
      ? input.notebook_path
      : input.file_path) as string;
    if (filePath) {
      const relativePath = toRelativePath(filePath, cwd);
      const existing = summary.filesChanged.get(relativePath);
      if (existing) {
        existing.count++;
      } else {
        summary.filesChanged.set(relativePath, {
          path: relativePath,
          operation: name,
          count: 1,
        });
      }
    }
  }

  // Bash → コマンドを記録
  if (name === "Bash") {
    const command = input.command as string;
    if (command) {
      summary.bashCommands.push(command);
    }
  }

  // Read/Grep/Glob → 調査パターン追跡
  if (name === "Read") {
    const filePath = input.file_path as string;
    if (filePath) {
      summary.investigations.push({
        type: "Read",
        target: toRelativePath(filePath, cwd),
      });
    }
  }
  if (name === "Grep") {
    const pattern = input.pattern as string;
    const path = input.path as string;
    if (pattern) {
      const target = path
        ? `\`${pattern}\` in \`${toRelativePath(path, cwd)}\``
        : `\`${pattern}\``;
      summary.investigations.push({ type: "Grep", target });
    }
  }
  if (name === "Glob") {
    const pattern = input.pattern as string;
    if (pattern) {
      summary.investigations.push({ type: "Glob", target: `\`${pattern}\`` });
    }
  }

  // Skill → スキル追跡
  if (name === "Skill") {
    const skill = input.skill as string;
    const args = input.args as string | undefined;
    if (skill) {
      summary.skills.push({ name: skill, args });
    }
  }

  // Task → エージェント追跡
  if (name === "Task") {
    const subagentType = input.subagent_type as string;
    const description = input.description as string;
    if (subagentType) {
      summary.agents.push({ subagentType, description: description || "" });
    }
  }
}

function extractOutcomes(summary: SessionSummary): void {
  for (const cmd of summary.bashCommands) {
    // git commit メッセージ抽出
    const commitMatch = cmd.match(
      /git commit -m "\$\(cat <<'EOF'\n(.+?)(?:\n|$)/,
    );
    if (commitMatch) {
      summary.outcomes.push(`**commit**: ${commitMatch[1]}`);
      continue;
    }
    // シンプルな git commit -m "..." パターン
    const simpleCommitMatch = cmd.match(/git commit -m "([^"]+)"/);
    if (simpleCommitMatch) {
      const firstLine = simpleCommitMatch[1].split("\n")[0];
      summary.outcomes.push(`**commit**: ${firstLine}`);
      continue;
    }

    // gh pr create --title
    const prMatch = cmd.match(/gh pr create --title "([^"]+)"/);
    if (prMatch) {
      summary.outcomes.push(`**PR**: ${prMatch[1]}`);
      continue;
    }

    // git push -u origin <branch>
    const pushMatch = cmd.match(/git push(?:\s+-u)?\s+origin\s+(\S+)/);
    if (pushMatch) {
      summary.outcomes.push(`**push**: ${pushMatch[1]}`);
    }
  }
}

function detectActivityTags(summary: SessionSummary): ActivityTag[] {
  const tags: ActivityTag[] = [];
  const cmds = summary.bashCommands.join("\n");
  const hasFileChanges = summary.filesChanged.size > 0;
  const hasBuildOrTest =
    /cargo (check|test|clippy|build)|yarn (tsc|lint|test|build)|npm (run )?(test|lint|build)|pnpm (run )?(test|lint|build)|bun (test|run)|deno (test|check|lint)|pytest|go test|make\b|rspec|rubocop/
      .test(cmds);
  const hasCommit = /git commit/.test(cmds);

  // PR作成
  if (/gh pr create/.test(cmds)) {
    tags.push("PR作成");
  }

  // PRレビュー（PR作成なし）
  if (
    !tags.includes("PR作成") && /gh pr (view|diff|checks|review)/.test(cmds)
  ) {
    tags.push("PRレビュー");
  }

  // 実装: ファイル変更 + ビルド/テスト + コミット
  if (hasFileChanges && (hasBuildOrTest || hasCommit)) {
    tags.push("実装");
  }

  // 調査: Read/Grep/Glob多数 + ファイル変更なし
  if (summary.investigations.length >= 5 && !hasFileChanges) {
    tags.push("調査");
  }

  // デバッグ
  if (/docker logs|error.*grep|grep.*error|CI.*log/i.test(cmds)) {
    tags.push("デバッグ");
  }

  // git操作
  if (/git (cherry-pick|rebase|merge|reset)/.test(cmds)) {
    tags.push("git操作");
  }

  // 設計
  const designFiles = [...summary.filesChanged.keys()].some((f) =>
    /plans\/|designs\//.test(f)
  );
  if (designFiles) {
    tags.push("設計");
  }

  return tags;
}

function toRelativePath(filePath: string, cwd: string): string {
  const homeDir = Deno.env.get("HOME") || "";

  // cwd配下のファイルは相対パスに変換
  if (filePath.startsWith(`${cwd}/`)) {
    return filePath.slice(cwd.length + 1);
  }

  // ホームディレクトリ配下は ~/ 形式に短縮
  if (homeDir && filePath.startsWith(`${homeDir}/`)) {
    return `~/${filePath.slice(homeDir.length + 1)}`;
  }

  return filePath;
}

function extractUserText(content: string | ContentItem[]): string {
  if (typeof content === "string") {
    return content;
  }
  if (Array.isArray(content)) {
    return content
      .filter((c): c is TextContent => c.type === "text" && "text" in c)
      .map((c) => c.text)
      .join("\n");
  }
  return "";
}

interface MarkdownParams {
  sessionId: string;
  reason: string;
  summary: SessionSummary;
}

function generateMarkdown(
  { sessionId, reason, summary }: MarkdownParams,
): string {
  const shortId = sessionId.slice(0, 8);

  // 時間表示の計算
  const timeStr = formatTimeRange(summary.startTime, summary.endTime);

  const lines: string[] = [];
  lines.push(`## セッション: ${shortId}`);
  lines.push(`- **時間**: ${timeStr}`);
  lines.push(`- **ブランチ**: ${summary.gitBranch}`);
  lines.push(`- **終了理由**: ${reason}`);

  if (summary.activityTags.length > 0) {
    lines.push(`- **活動**: ${summary.activityTags.join(", ")}`);
  }

  const { inputTokens, outputTokens, cacheTokens } = summary.tokenUsage;
  if (inputTokens > 0 || outputTokens > 0) {
    lines.push(
      `- **トークン**: in:${formatNumber(inputTokens)} / out:${
        formatNumber(outputTokens)
      } / cache:${formatNumber(cacheTokens)}`,
    );
  }

  lines.push("");

  // 会話ログ
  if (summary.userMessages.length > 0) {
    lines.push("### 会話");
    for (const msg of summary.userMessages) {
      const truncatedText = truncateText(msg.text, 500);
      lines.push("#### ユーザー");
      lines.push(truncatedText);
      lines.push("");
    }

    if (summary.assistantFinalResponse) {
      const truncatedResponse = truncateText(
        summary.assistantFinalResponse,
        1000,
      );
      lines.push("#### Claude（最終回答）");
      lines.push(truncatedResponse);
      lines.push("");
    }
  }

  // 成果物
  if (summary.outcomes.length > 0) {
    lines.push("### 成果");
    for (const outcome of summary.outcomes) {
      lines.push(`- ${outcome}`);
    }
    lines.push("");
  }

  // 変更ファイル
  if (summary.filesChanged.size > 0) {
    lines.push("### 変更ファイル");
    for (const [, change] of summary.filesChanged) {
      const countStr = change.count > 1 ? ` x${change.count}` : "";
      lines.push(`- \`${change.path}\` (${change.operation}${countStr})`);
    }
    lines.push("");
  }

  // 調査（重複を除いて最大15件）
  if (summary.investigations.length > 0) {
    lines.push("### 調査");
    const seen = new Set<string>();
    let count = 0;
    for (const inv of summary.investigations) {
      const key = `${inv.type}: ${inv.target}`;
      if (seen.has(key)) continue;
      seen.add(key);
      if (count >= 15) break;
      lines.push(`- ${inv.type}: ${inv.target}`);
      count++;
    }
    if (seen.size > 15) {
      lines.push(`- ... and ${seen.size - 15} more`);
    }
    lines.push("");
  }

  // スキル・エージェント
  if (summary.skills.length > 0 || summary.agents.length > 0) {
    lines.push("### スキル・エージェント");
    for (const skill of summary.skills) {
      const argsStr = skill.args ? `: ${skill.args}` : "";
      lines.push(`- Skill: \`${skill.name}\`${argsStr}`);
    }
    for (const agent of summary.agents) {
      const descStr = agent.description ? `: ${agent.description}` : "";
      lines.push(`- Agent[${agent.subagentType}]${descStr}`);
    }
    lines.push("");
  }

  // 実行コマンド（重複を除いて表示）
  if (summary.bashCommands.length > 0) {
    lines.push("### 実行コマンド");
    const uniqueCommands = [...new Set(summary.bashCommands)];
    const maxShow = 20;
    for (const cmd of uniqueCommands.slice(0, maxShow)) {
      const truncatedCmd = truncateText(cmd.split("\n")[0], 200);
      lines.push(`- \`${truncatedCmd}\``);
    }
    if (uniqueCommands.length > maxShow) {
      lines.push(`- ... and ${uniqueCommands.length - maxShow} more commands`);
    }
    lines.push("");
  }

  lines.push("---");
  lines.push("");

  return lines.join("\n");
}

function formatTimeRange(
  startTime: string | null,
  endTime: string | null,
): string {
  if (!startTime) return "不明";

  const start = new Date(startTime);
  const end = endTime ? new Date(endTime) : start;

  const fmt = (d: Date) =>
    d.toLocaleString("ja-JP", {
      timeZone: "Asia/Tokyo",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
    });

  const startStr = fmt(start);
  const endStr = fmt(end);

  const durationMs = end.getTime() - start.getTime();
  const durationMin = Math.round(durationMs / 60000);

  // 同日なら時刻のみ、異日ならフル表示
  const startDate = start.toLocaleDateString("ja-JP", {
    timeZone: "Asia/Tokyo",
  });
  const endDate = end.toLocaleDateString("ja-JP", { timeZone: "Asia/Tokyo" });

  if (startDate === endDate) {
    const startHM = start.toLocaleTimeString("ja-JP", {
      timeZone: "Asia/Tokyo",
      hour: "2-digit",
      minute: "2-digit",
    });
    const endHM = end.toLocaleTimeString("ja-JP", {
      timeZone: "Asia/Tokyo",
      hour: "2-digit",
      minute: "2-digit",
    });
    return `${startDate} ${startHM} → ${endHM} (${durationMin}分)`;
  }

  return `${startStr} → ${endStr} (${durationMin}分)`;
}

function formatNumber(n: number): string {
  return n.toLocaleString("en-US");
}

function truncateText(text: string, maxLength: number): string {
  const normalized = text.replace(/\r\n/g, "\n").trim();
  if (normalized.length <= maxLength) {
    return normalized;
  }
  return `${normalized.slice(0, maxLength)}...`;
}

main();
