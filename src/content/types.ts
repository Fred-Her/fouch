import type { en } from "./en";

/** Structure derived from the English source of truth: every leaf is a
 * string (templates use {placeholders}), so the whole dictionary is
 * JSON-serializable and can cross the server -> client boundary.
 * es.ts is typed as Dictionary, so a missing Spanish key is a
 * compile-time error, not a runtime surprise. */
type DeepString<T> = T extends string
  ? string
  : T extends readonly (infer U)[]
    ? DeepString<U>[]
    : { [K in keyof T]: DeepString<T[K]> };

export type Dictionary = DeepString<typeof en>;
