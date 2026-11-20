import type { Register, SessionMessage } from "claude-code";

const MIN_LATIN = 40;

const FUNCTION_WORDS = new Set(
  "a an the is are was were be been has have had do does did not no and or but if so to of in on at by for from with without into as that this it its all every i you we they there which yet"
    .split(" "),
);

const ENGLISH_REQUEST =
  /英語(?:だけ|のみ)?で|英訳|英文|in English|English only/i;

const REASON =
  "本文が英語です。同じ内容を日本語で書き直してください (コード・識別子・コミットメッセージは原文のまま)。";

export function isUntranslated(text: string): boolean {
  const prose = text
    .replace(/(```|~~~)[\s\S]*?\1/g, "")
    .replace(/`[^`\n]*`/g, "")
    .replace(/https?:\/\/\S+/g, "");
  if ((prose.match(/[A-Za-z]/g)?.length ?? 0) < MIN_LATIN) return false;
  if (!/[\p{Script=Hiragana}\p{Script=Katakana}]/u.test(prose)) return true;
  let japanese = 0;
  let english = 0;
  for (const sentence of prose.split(/(?<=[。！？])|\n+/)) {
    if (JAPANESE_END.test(sentence.replace(TRAILING_ASIDE, ""))) japanese++;
    else if (sentence.split(/[^\w.\/-]+/).some(isFunctionWord)) english++;
  }
  return english > japanese;
}

const JAPANESE_END =
  /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}ー][\s\p{P}]*$/u;

const TRAILING_ASIDE = /\s*[(（][^()（）]*[)）][\s\p{P}]*$/u;

const isFunctionWord = (word: string) =>
  FUNCTION_WORDS.has(word.replace(/\.$/, "").toLowerCase());

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
