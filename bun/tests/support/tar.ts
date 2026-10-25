// Reads and writes gzip-compressed tar archives (npm package archives) for the
// npm test fixtures: the loopback registry reads `package.json` from an
// archive, and the fixture scripts write archives with fixed modes and mtimes.
// Only the entry kinds those archives use are handled: regular files,
// directories, ustar `prefix` names, pax `path` records and GNU long names.

export interface TarEntry {
  /** The entry's path inside the archive, `/`-separated. */
  name: string;
  /** "file", "directory" or "other" when reading; "file" or "directory" when writing. */
  type: "file" | "directory" | "other";
  /** File contents; empty for a directory. */
  data: Uint8Array;
  /** Permission bits; 0o644 for files and 0o755 for directories when not given. */
  mode?: number;
}

const BLOCK = 512;
const decoder = new TextDecoder();
const encoder = new TextEncoder();

function field(header: Uint8Array, offset: number, length: number): string {
  const bytes = header.subarray(offset, offset + length);
  const end = bytes.indexOf(0);
  return decoder.decode(end === -1 ? bytes : bytes.subarray(0, end));
}

function octal(header: Uint8Array, offset: number, length: number): number {
  const text = field(header, offset, length).trim();
  return text === "" ? 0 : parseInt(text, 8);
}

function paxPath(data: Uint8Array): string | undefined {
  let rest = decoder.decode(data);
  while (rest.length > 0) {
    const space = rest.indexOf(" ");
    const length = Number(rest.slice(0, space));
    const record = rest.slice(space + 1, length - 1);
    rest = rest.slice(length);
    if (record.startsWith("path=")) return record.slice("path=".length);
  }
  return undefined;
}

/** Returns the entries of a gzip-compressed tar archive. */
export function readTgz(archive: Uint8Array): TarEntry[] {
  const tar = Bun.gunzipSync(archive);
  const entries: TarEntry[] = [];
  let offset = 0;
  let longName: string | undefined;
  while (offset + BLOCK <= tar.length) {
    const header = tar.subarray(offset, offset + BLOCK);
    if (header.every((b) => b === 0)) break;
    const size = octal(header, 124, 12);
    const type = String.fromCharCode(header[156]);
    const data = tar.slice(offset + BLOCK, offset + BLOCK + size);
    offset += BLOCK + Math.ceil(size / BLOCK) * BLOCK;
    if (type === "x") {
      longName = paxPath(data) ?? longName;
      continue;
    }
    if (type === "L") {
      longName = decoder.decode(data).replace(/\0+$/, "");
      continue;
    }
    if (type === "g") continue;
    const prefix = field(header, 345, 155);
    const name = longName ?? (prefix ? `${prefix}/${field(header, 0, 100)}` : field(header, 0, 100));
    longName = undefined;
    entries.push({
      name,
      type: type === "0" || type === "\0" ? "file" : type === "5" ? "directory" : "other",
      data,
      mode: octal(header, 100, 8),
    });
  }
  return entries;
}

function writeField(header: Uint8Array, offset: number, length: number, value: string) {
  const bytes = encoder.encode(value);
  if (bytes.length > length) throw new Error(`tar header field too long: ${value}`);
  header.set(bytes, offset);
}

function writeOctal(header: Uint8Array, offset: number, length: number, value: number) {
  writeField(header, offset, length, value.toString(8).padStart(length - 1, "0"));
}

function header(name: string, prefix: string, type: string, size: number, mode: number, mtime: number): Uint8Array {
  const h = new Uint8Array(BLOCK);
  writeField(h, 0, 100, name);
  writeOctal(h, 100, 8, mode);
  writeOctal(h, 108, 8, 0);
  writeOctal(h, 116, 8, 0);
  writeOctal(h, 124, 12, size);
  writeOctal(h, 136, 12, mtime);
  h.fill(0x20, 148, 156);
  writeField(h, 156, 1, type);
  writeField(h, 257, 6, "ustar");
  writeField(h, 263, 2, "00");
  writeField(h, 345, 155, prefix);
  const sum = h.reduce((a, b) => a + b, 0);
  writeField(h, 148, 8, `${sum.toString(8).padStart(6, "0")}\0 `);
  return h;
}

function padded(data: Uint8Array): Uint8Array {
  const out = new Uint8Array(Math.ceil(data.length / BLOCK) * BLOCK);
  out.set(data);
  return out;
}

// Splits a name into a ustar prefix and name, or returns undefined when it does
// not fit.
function splitName(name: string): [string, string] | undefined {
  if (encoder.encode(name).length <= 100) return ["", name];
  for (let i = name.indexOf("/"); i !== -1; i = name.indexOf("/", i + 1)) {
    const prefix = name.slice(0, i);
    const rest = name.slice(i + 1);
    if (encoder.encode(prefix).length <= 155 && encoder.encode(rest).length <= 100) return [prefix, rest];
  }
  return undefined;
}

function paxRecord(key: string, value: string): string {
  // The record's length counts its own decimal digits.
  const body = ` ${key}=${value}\n`;
  const bodyLength = encoder.encode(body).length;
  let length = bodyLength + String(bodyLength).length;
  length = bodyLength + String(length).length;
  return `${length}${body}`;
}

/**
 * Writes entries, in the given order, as a gzip-compressed tar archive with
 * uid and gid 0, the given mtime (seconds) and fixed modes, so that the same
 * entries always give the same bytes.
 */
export function writeTgz(entries: TarEntry[], mtime = 0): Uint8Array {
  const blocks: Uint8Array[] = [];
  for (const entry of entries) {
    const type = entry.type === "directory" ? "5" : "0";
    const mode = entry.mode ?? (entry.type === "directory" ? 0o755 : 0o644);
    const data = entry.type === "directory" ? new Uint8Array() : entry.data;
    let split = splitName(entry.name);
    if (split === undefined) {
      const pax = encoder.encode(paxRecord("path", entry.name));
      blocks.push(header("././@PaxHeader", "", "x", pax.length, 0o644, mtime), padded(pax));
      split = ["", entry.name.slice(-100)];
    }
    blocks.push(header(split[1], split[0], type, data.length, mode, mtime), padded(data));
  }
  blocks.push(new Uint8Array(2 * BLOCK));
  const tar = new Uint8Array(blocks.reduce((n, b) => n + b.length, 0));
  let offset = 0;
  for (const b of blocks) {
    tar.set(b, offset);
    offset += b.length;
  }
  return Bun.gzipSync(tar, { level: 9 });
}

/** Returns the parsed `package.json` of an npm package archive (any top-level directory). */
export function packageJson(archive: Uint8Array): Record<string, any> {
  for (const entry of readTgz(archive)) {
    if (entry.type === "file" && /^[^/]+\/package\.json$/.test(entry.name)) {
      return JSON.parse(decoder.decode(entry.data));
    }
  }
  throw new Error("the archive holds no <top-level directory>/package.json");
}
