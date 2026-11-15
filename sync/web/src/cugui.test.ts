import { expect, test } from "bun:test";
import { dictionaryFile, folderBundle, settingsDump } from "./cugui";
import type { Item } from "./vault";

const vault = (records: Record<string, Record<string, unknown>>) => ({
  items: (collection: string): Item[] =>
    Object.entries(records[collection] ?? {}).map(([id, value]) => ({ collection, id, value: JSON.stringify(value), time: "" })),
});

test("settings dump matches the app's export", () => {
  const dump = settingsDump(
    vault({
      settings: { app_theme: 2, locale: "de" },
      cards: { c1: { id: "c1", name: "Office" } },
      plugins: { p1: { id: "p1" } },
    }),
  );
  expect(JSON.parse(dump)).toEqual({
    app_theme: 2,
    locale: "de",
    cards: [{ id: "c1", name: "Office" }],
    plugins_v1: [{ id: "p1" }],
  });
});

test("folder export holds the folder's subtree", () => {
  const bundle = JSON.parse(
    folderBundle(
      "cards",
      "root",
      vault({
        card_folders: { root: { id: "root" }, child: { id: "child", parentId: "root" }, other: { id: "other" } },
        cards: { a: { id: "a", folderId: "child" }, b: { id: "b", folderId: "other" }, c: { id: "c" } },
      }),
    ),
  );
  expect(bundle).toEqual({
    format: "chameleon-ultra-gui-folder",
    version: 1,
    rootFolderId: "root",
    folders: [{ id: "root" }, { id: "child", parentId: "root" }],
    cards: [{ id: "a", folderId: "child" }],
  });
});

test("dictionary file is the app's .dic", () => {
  expect(dictionaryFile({ id: "d", name: "d", keys: [[255, 0, 1, 2, 3, 171]] })).toBe("FF00010203AB\n");
});
