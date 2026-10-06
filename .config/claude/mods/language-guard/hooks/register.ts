import type { Register, SessionMessage } from "claude-code";

const MIN_LATIN = 40;

const ENGLISH_REQUEST =
  /英語(?:だけ|のみ)?で|英訳|英文|in English|English only/i;

const REASON =
  "本文が英語です。同じ内容を日本語で書き直してください (コード・識別子・コミットメッセージは原文のまま)。";

export function isUntranslated(text: string): boolean {
  const prose = text
    .replace(/(```|~~~)[\s\S]*?\1/g, "")
    .replace(/`[^`\n]*`/g, "")
    .replace(/https?:\/\/\S+/g, "");
  if (/[\p{Script=Hiragana}\p{Script=Katakana}]/u.test(prose)) return false;
  return (prose.match(/[A-Za-z]/g)?.length ?? 0) >= MIN_LATIN;
}

export function requestsEnglish(messages: readonly SessionMessage[]): boolean {
  const prompt = messages.findLast((m) =>
    m.role === "user" && !m.toolResults?.length && m.text !== ""
  );
  return ENGLISH_REQUEST.test(prompt?.text ?? "");
}

export const register: Register = (on) => {
  on("classic.Stop", async ($, e, next) => {
    if (
      isUntranslated(e.last_assistant_message ?? "") &&
      !requestsEnglish(await $.session.messages())
    ) {
      return { block: REASON };
    }
    return next(e);
  }).catch((_$, e, next) => next(e));
};
