import { expect, test } from 'claude-code/testing';

const flowchart = 'graph LR\nA --> B\n';
const pie = 'pie\n"a": 1\n';

function draw(text: string) {
  return {
    surface: 'terminal' as const,
    component: 'AssistantMessage' as const,
    requestId: 'm1',
    viewport: { columns: 84, rows: 40 },
    props: { text, isFirstOfReply: true },
  };
}

test('mermaid fences become ASCII, unsupported ones stay as written', async ($, on) => {
  const runs: { argv: readonly string[]; stdin?: string }[] = [];
  on('process.run', (_$, e) => {
    runs.push({ argv: e.argv, stdin: e.init?.stdin });
    return e.init?.stdin === flowchart
      ? {
          value: {
            exitCode: 0,
            stdout: '┌─┐\n│A├─►\n',
            stderr: '',
            isStdoutTruncated: false,
            isStderrTruncated: false,
          },
        }
      : {
          value: {
            exitCode: 1,
            stdout: '',
            stderr: "unsupported graph type 'pie'",
            isStdoutTruncated: false,
            isStderrTruncated: false,
          },
        };
  });
  const prose: { text: string; isFirstOfReply: boolean }[] = [];
  on('ui.render', (_$, e) => {
    if (e.component === 'AssistantMessage') {
      const { text, isFirstOfReply } = e.props;
      prose.push({ text, isFirstOfReply });
    }
    return { type: 'Text', props: {}, children: [] };
  });

  const text = `before\n\`\`\`mermaid\n${flowchart}\`\`\`\nmid\n\`\`\`mermaid\n${pie}\`\`\`\nafter`;
  const tree = await $.ui.render(draw(text));
  await $.ui.render(draw(text));

  expect(prose.slice(0, 2)).toEqual([
    { text: 'before', isFirstOfReply: true },
    { text: `mid\n\`\`\`mermaid\n${pie}\`\`\`\nafter`, isFirstOfReply: false },
  ]);
  expect(painted(tree)).toEqual([
    ['subtle', '┌─┐'],
    ['subtle', '│'],
    ['bold', 'A'],
    ['subtle', '├─'],
    ['claude', '►'],
  ]);
  expect(runs).toEqual([
    {
      argv: ['mermaid-ascii', '-f', '-', '--max-width', '80'],
      stdin: flowchart,
    },
    { argv: ['mermaid-ascii', '-f', '-', '--max-width', '80'], stdin: pie },
  ]);
});

test('unclosed fences, fences quoted in an outer fence, and plain replies pass through', async ($, on) => {
  let ran = false;
  on('process.run', () => {
    ran = true;
    return {
      value: {
        exitCode: 0,
        stdout: 'x',
        stderr: '',
        isStdoutTruncated: false,
        isStderrTruncated: false,
      },
    };
  });
  const drawn: string[] = [];
  on('ui.render', (_$, e) => {
    if (e.component === 'AssistantMessage') drawn.push(e.props.text);
    return { type: 'Text', props: {}, children: [] };
  });

  const texts = [
    'no diagram here',
    '```mermaid\ngraph LR\nA --> B\n',
    `\`\`\`\`markdown\n\`\`\`mermaid\n${flowchart}\`\`\`\n\`\`\`\``,
    `~~~\n\`\`\`mermaid\n${flowchart}\`\`\`\n~~~`,
    `\`\`\`sh\necho\n\`\`\`mermaid\n${flowchart}\`\`\``,
  ];
  for (const text of texts) await $.ui.render(draw(text));
  expect(drawn).toEqual(texts);
  expect(ran).toBe(false);
});

test('a missing mermaid-ascii binary leaves the reply untouched', async ($, on) => {
  on('process.run', () => {
    throw new Error('spawn mermaid-ascii ENOENT');
  });
  const drawn: string[] = [];
  on('ui.render', (_$, e) => {
    if (e.component === 'AssistantMessage') drawn.push(e.props.text);
    return { type: 'Text', props: {}, children: [] };
  });

  const text = `\`\`\`mermaid\n${flowchart}\`\`\``;
  await $.ui.render(draw(text));
  expect(drawn).toEqual([text]);
});

type Node = {
  props?: { color?: string; bold?: boolean };
  children?: unknown[];
};

function painted(node: unknown): [string, string][] {
  if (typeof node !== 'object' || node === null) return [];
  const { props, children = [] } = node as Node;
  const strings = children.filter((c): c is string => typeof c === 'string');
  const style = props?.color ?? (props?.bold ? 'bold' : undefined);
  const own: [string, string][] =
    style && strings.length ? [[style, strings.join('')]] : [];
  return [...own, ...children.flatMap(painted)];
}

test('tilde and spaced fences convert, and prose keeps its indentation', async ($, on) => {
  const sources: (string | undefined)[] = [];
  on('process.run', (_$, e) => {
    if (e.argv[0] === 'mermaid-ascii') sources.push(e.init?.stdin);
    return {
      value: {
        exitCode: 0,
        stdout: 'A',
        stderr: '',
        isStdoutTruncated: false,
        isStderrTruncated: false,
      },
    };
  });
  const prose: string[] = [];
  on('ui.render', (_$, e) => {
    if (e.component === 'AssistantMessage') prose.push(e.props.text);
    return { type: 'Text', props: {}, children: [] };
  });

  await $.ui.render(draw('~~~mermaid\ngraph LR\nT --> U\n~~~'));
  await $.ui.render(draw('``` mermaid\ngraph LR\nS --> T\n```'));
  await $.ui.render(
    draw(
      `    echo hello\n\n\`\`\`mermaid\n${flowchart}\`\`\`\n\n    echo bye\n`,
    ),
  );

  expect(sources).toEqual([
    'graph LR\nT --> U\n',
    'graph LR\nS --> T\n',
    flowchart,
  ]);
  expect(prose).toEqual(['    echo hello', '    echo bye']);
});

test('a reply opening with a diagram draws its own bullet', async ($, on) => {
  on('process.run', (_$, e) => ({
    value: {
      exitCode: 0,
      stdout: e.argv[0] === 'uname' ? 'Darwin\n' : '┌─┐',
      stderr: '',
      isStdoutTruncated: false,
      isStderrTruncated: false,
    },
  }));
  const prose: { text: string; isFirstOfReply: boolean }[] = [];
  on('ui.render', (_$, e) => {
    if (e.component === 'AssistantMessage') {
      const { text, isFirstOfReply } = e.props;
      prose.push({ text, isFirstOfReply });
    }
    return { type: 'Text', props: {}, children: [] };
  });

  const tree = await $.ui.render(
    draw(`\`\`\`mermaid\n${flowchart}\`\`\`\nafter`),
  );
  expect(painted(tree)).toEqual([
    ['text', '⏺'],
    ['subtle', '┌─┐'],
  ]);
  expect(prose).toEqual([{ text: 'after', isFirstOfReply: false }]);
});

test('a run that could not finish is retried on the next draw', async ($, on) => {
  let calls = 0;
  on('process.run', () => {
    calls += 1;
    if (calls === 1) throw new Error('spawn mermaid-ascii ENOENT');
    return {
      value: {
        exitCode: 0,
        stdout: '┌─┐',
        stderr: '',
        isStdoutTruncated: false,
        isStderrTruncated: false,
      },
    };
  });
  on('ui.render', () => ({ type: 'Text', props: {}, children: [] }));

  const reply = {
    ...draw(`\`\`\`mermaid\n${flowchart}\`\`\``),
    props: { text: `\`\`\`mermaid\n${flowchart}\`\`\``, isFirstOfReply: false },
  };
  await $.ui.render(reply);
  const tree = await $.ui.render(reply);
  expect(calls).toBe(2);
  expect(painted(tree)).toEqual([['subtle', '┌─┐']]);
});
