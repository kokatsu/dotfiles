export type LineFile = {
  exists: (path: string) => Promise<boolean>;
  read: (path: string) => Promise<string>;
  write: (path: string, text: string) => Promise<void>;
};

// `$.fs` has no append, so each line is a read-modify-write; chaining them
// keeps judges that finish close together from overwriting each other.
export function lineAppender() {
  let last: Promise<void> = Promise.resolve();
  return (file: LineFile, path: string, line: string): Promise<void> => {
    const run = last.then(async () => {
      const previous = (await file.exists(path)) ? await file.read(path) : "";
      await file.write(path, previous + line + "\n");
    });
    last = run.catch(() => {});
    return run;
  };
}
