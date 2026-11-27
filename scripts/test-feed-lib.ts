import { spawnSync } from "node:child_process";

export function run(command: string, args: string[], input: string) {
  const { error, status, signal, stdout } = spawnSync(command, args, {
    input,
    encoding: "utf8",
  });
  if (error) throw error;
  if (status === null) throw new Error(`${command} terminated with ${signal}`);
  return { code: status, stdout };
}
