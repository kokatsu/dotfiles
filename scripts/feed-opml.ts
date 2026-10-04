import { rec } from "./feed-entries.ts";

export interface OpmlFeed {
  name: string;
  category: string;
  xmlUrl: string;
  htmlUrl: string;
}

export function parseOpml(input: string): OpmlFeed[] {
  const documents: unknown = JSON.parse(input);
  if (!Array.isArray(documents)) throw new Error("expected OPML documents");
  const feeds: OpmlFeed[] = [];

  function outlines(value: unknown, category: string): void {
    if (value === undefined) return;
    for (const raw of Array.isArray(value) ? value : [value]) {
      const outline = rec(raw);
      if (!outline) throw new Error("invalid OPML outline");
      const name = outline["+@text"];
      const xmlUrl = outline["+@xmlUrl"];
      if (xmlUrl !== undefined) {
        if (
          typeof name !== "string" || !name || typeof xmlUrl !== "string" ||
          !xmlUrl
        ) {
          throw new Error("feed outline requires text and xmlUrl");
        }
        const htmlUrl = outline["+@htmlUrl"];
        feeds.push({
          name,
          category,
          xmlUrl,
          htmlUrl: typeof htmlUrl === "string" && htmlUrl ? htmlUrl : xmlUrl,
        });
      }
      outlines(
        outline.outline,
        xmlUrl === undefined && typeof name === "string" && name
          ? name
          : category,
      );
    }
  }

  for (const document of documents) {
    const root = rec(document);
    const elements = Object.keys(root ?? {}).filter((key) =>
      !key.startsWith("+")
    );
    const opml = rec(root?.opml);
    if (
      elements.length !== 1 || elements[0] !== "opml" || !opml ||
      !("body" in opml)
    ) {
      throw new Error("expected an OPML document with a body");
    }
    const body = opml.body === null ? {} : rec(opml.body);
    if (!body) throw new Error("invalid OPML body");
    outlines(body.outline, "");
  }
  return feeds;
}

// Persisted status keys can contain XML entities. Decode once, only when the
// old key is no longer configured, and refuse to overwrite progress.
export function migrateFeedNames<T>(
  feeds: Record<string, T>,
  entries: OpmlFeed[],
): Record<string, T> {
  const names = new Set(entries.map((entry) => entry.name));
  const result = new Map(Object.entries(feeds));
  const entities: Record<string, string> = {
    amp: "&",
    lt: "<",
    gt: ">",
    quot: '"',
    apos: "'",
  };
  for (const [name, feed] of Object.entries(feeds)) {
    if (names.has(name)) continue;
    const decoded = name.replace(
      /&(amp|lt|gt|quot|apos|#\d+|#x[\da-fA-F]+);/g,
      (_, entity: string) => {
        if (!entity.startsWith("#")) return entities[entity];
        const point = entity.startsWith("#x")
          ? parseInt(entity.slice(2), 16)
          : Number(entity.slice(1));
        return point > 0 && point <= 0x10ffff &&
            !(point >= 0xd800 && point <= 0xdfff)
          ? String.fromCodePoint(point)
          : `&${entity};`;
      },
    );
    if (decoded === name || !names.has(decoded)) continue;
    if (result.has(decoded)) {
      throw new Error(`conflicting feed state: ${name} / ${decoded}`);
    }
    result.set(decoded, feed);
    result.delete(name);
  }
  return Object.fromEntries(result);
}

if (import.meta.main) {
  try {
    console.log(
      JSON.stringify(parseOpml(await new Response(Deno.stdin.readable).text())),
    );
  } catch (error) {
    console.error(
      `parse-opml: ${error instanceof Error ? error.message : String(error)}`,
    );
    Deno.exit(1);
  }
}
