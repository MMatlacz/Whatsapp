// Shared by the Node main process and the bundled renderer.
// Offsets always refer to the original text.

export interface Token {
  id: number;
  text: string;
  start: number;
  end: number;
}

export function tokenize(text: string): Token[] {
  const tokens: Token[] = [];
  const pattern = /@[\p{L}\p{M}\p{N}_.-]+|[\p{L}\p{M}\p{N}]+(?:['’\-][\p{L}\p{M}\p{N}]+)*/gu;
  for (const match of String(text).matchAll(pattern)) {
    tokens.push({ id: tokens.length, text: match[0], start: match.index, end: match.index + match[0].length });
  }
  return tokens;
}