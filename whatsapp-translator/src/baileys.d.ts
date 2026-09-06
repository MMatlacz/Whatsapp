// Baileys v7 is ESM-only, ships without bundled types in this install, and is
// treated here as an opaque runtime handle. Its message shapes are largely
// protobuf-derived; the gateway only reads a few documented fields.
declare module 'baileys' {
  const baileys: any;
  export = baileys;
}