import { expect, test } from 'claude-code/testing';

import { splitHeadings } from './register';

function draw(text: string) {
  return {
    surface: 'terminal' as const,
    component: 'AssistantMessage' as const,
    requestId: 'm1',
    viewport: { columns: 84, rows: 40 },
    props: { text, isFirstOfReply: false },
  };
}

test('headings split out, fenced ones stay prose', () => {
  const text = [
    'intro',
    '## Plan `x` **y** *z* ~~w~~',
    'body',
    '```sh',
    '# comment',
    '```',
    '### Done ###',
  ].join('\n');
  expect(splitHeadings(text)).toEqual([
    { markdown: 'intro' },
    { level: 2, title: 'Plan x y z w' },
    { markdown: 'body\n```sh\n# comment\n```' },
    { level: 3, title: 'Done' },
  ]);
});

test('code spans in a heading keep their marks', () => {
  expect(splitHeadings('# Match `**/*.ts` and **[docs](u)**')).toEqual([
    { level: 1, title: 'Match **/*.ts and docs' },
  ]);
  expect(splitHeadings('# ``**/*.ts`` or `` a`*b* ``')).toEqual([
    { level: 1, title: '**/*.ts or a`*b*' },
  ]);
});

test('a reply without headings goes to the engine whole', async ($, on) => {
  const seen: string[] = [];
  on('ui.render', (_$, e) => {
    if (e.component === 'AssistantMessage') seen.push(e.props.text);
    return { type: 'Text', props: {}, children: [] };
  });
  await $.ui.render(draw('plain\n#hashtag'));
  expect(seen).toEqual(['plain\n#hashtag']);
});

test('a heading is drawn as colored Text, prose through the engine', async ($, on) => {
  const seen: string[] = [];
  on('ui.render', (_$, e) => {
    if (e.component === 'AssistantMessage') seen.push(e.props.text);
    return { type: 'Text', props: {}, children: ['engine'] };
  });
  const ui = await $.ui.mount({
    ...draw('# Title\nbody'),
    plugin: 'heading-colors',
  });
  expect(seen).toEqual(['body']);
  expect((await ui.find({ type: 'Text', text: 'Title' }))?.text).toBe('Title');
  await ui.unmount();
});
