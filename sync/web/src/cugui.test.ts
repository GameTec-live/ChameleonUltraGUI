import { expect, test } from "bun:test";
import { dictionaryFile, editError, folderBundle, settingsDump } from "./cugui";
import type { Item } from "./vault";

const vault = (records: Record<string, Record<string, unknown>>) => ({
  items: (collection: string): Item[] =>
    Object.entries(records[collection] ?? {}).map(([id, value]) => ({ collection, id, value: JSON.stringify(value), time: "", version: "1" })),
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

test("edits the app would choke on are refused", () => {
  const item = (collection: string, id: string, value: unknown) => ({ collection, id, value: JSON.stringify(value), time: "", version: "1" });
  expect(editError(item("settings", "app_theme", 1), 2)).toBeUndefined();
  expect(editError(item("settings", "app_theme", 1), 3)).toBeDefined();
  expect(editError(item("settings", "locale", "en"), "de-AT")).toBeUndefined();
  expect(editError(item("settings", "locale", "en"), "a-b-c")).toBeDefined();
  const card = item("cards", "c1", { id: "c1", name: "Office", data: [[1]] });
  expect(editError(card, { id: "c1", name: "Gym", data: [], extra: {} })).toBeUndefined();
  expect(editError(card, { id: "c1", name: "Gym", data: "x" })).toBeDefined();
  expect(editError(card, { id: "c2", name: "Gym", data: [] })).toBeDefined();
});
