import { existsSync } from "node:fs";
import path from "node:path";

function trimOuterQuotes(value: string): string {
  const text = value.trim();
  if (!text) {
    return text;
  }

  const startsWithDouble = text.startsWith('"');
  const endsWithDouble = text.endsWith('"');
  const startsWithSingle = text.startsWith("'");
  const endsWithSingle = text.endsWith("'");

  if ((startsWithDouble && endsWithDouble) || (startsWithSingle && endsWithSingle)) {
    return text.slice(1, -1).trim();
  }

  return text;
}

function hasExtension(command: string): boolean {
  return path.extname(command) !== "";
}

function isPathLike(command: string): boolean {
  return command.includes("\\") || command.includes("/") || /^[a-zA-Z]:/.test(command);
}

export function resolveCommandForSpawn(commandRaw: string): string {
  const command = trimOuterQuotes(commandRaw);
  if (!command) {
    return command;
  }

  if (process.platform !== "win32") {
    return command;
  }

  if (hasExtension(command)) {
    return command;
  }

  const pathextRaw = process.env.PATHEXT ?? ".COM;.EXE;.BAT;.CMD";
  const extensions = pathextRaw
    .split(";")
    .map((entry) => entry.trim().toLowerCase())
    .filter(Boolean);
  const uniqueExtensions = [...new Set(extensions)];

  if (isPathLike(command)) {
    for (const ext of uniqueExtensions) {
      const candidate = `${command}${ext}`;
      if (existsSync(candidate)) {
        return candidate;
      }
    }
    return command;
  }

  const pathValue = process.env.Path ?? process.env.PATH ?? "";
  const pathEntries = pathValue
    .split(";")
    .map((entry) => entry.trim())
    .filter(Boolean);

  for (const dir of pathEntries) {
    for (const ext of uniqueExtensions) {
      const candidate = path.join(dir, `${command}${ext}`);
      if (existsSync(candidate)) {
        return candidate;
      }
    }
  }

  return command;
}
