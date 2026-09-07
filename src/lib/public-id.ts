import { customAlphabet } from "nanoid";

// No 0/O/1/I/l — avoids visually ambiguous characters in a link people
// might read aloud or retype. 9 chars over this 32-symbol alphabet is
// ~46 bits of entropy — not guessable, plenty for this scale.
const alphabet = "23456789abcdefghjkmnpqrstuvwxyz";
const generate = customAlphabet(alphabet, 9);

export function generatePublicId(): string {
  return generate();
}