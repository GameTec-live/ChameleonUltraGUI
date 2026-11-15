// Chameleon Ultra GUI data formats: what the app stores and imports.
import type { Item } from "./vault";

/** Collections of JSON objects with an `id`, and the app preference each is stored under. */
export const LIST_PREFS = {
  cards: "cards",
  card_folders: "card_folders",
  dictionaries: "dictionaries",
  dictionary_folders: "dictionary_folders",
  plugins: "plugins_v1",
} as const;

export type Folder = { id: string; name: string; color?: string; parentId?: string };
export type Card = { id: string; name: string; uid?: string; tag?: number; color?: string; folderId?: string };
export type Dictionary = { id: string; name: string; color?: string; keys: number[][]; folderId?: string };

type Items = { items(collection: string): Item[] };

export const parse = <T>(item: Item) => JSON.parse(item.value) as T;

/** `TagType` names from the app's `definitions.dart`. */
const TAG_NAMES: Record<number, string> = {
  100: "EM410X",
  101: "EM410X/16",
  102: "EM410X/32",
  103: "EM410X/64",
  104: "EM410X Electra",
  150: "PAC/Stanley",
  170: "Viking",
  180: "Jablotron",
  200: "HID Prox",
  201: "ioProx",
  310: "IDTECK",
  1000: "MIFARE Mini",
  1001: "MIFARE Classic 1K",
  1002: "MIFARE Classic 2K",
  1003: "MIFARE Classic 4K",
  1100: "NTAG213",
  1101: "NTAG215",
  1102: "NTAG216",
  1103: "MIFARE Ultralight",
  1104: "MIFARE Ultralight C",
  1105: "MIFARE Ultralight EV1 (11)",
  1106: "MIFARE Ultralight EV1 (21)",
  1107: "NTAG210",
  1108: "NTAG212",
  3000: "ISO 14443-4",
};

export const tagName = (tag?: number) => (tag === undefined ? "" : (TAG_NAMES[tag] ?? `Type ${tag}`));

/**
 * The app's settings export (`dumpSettingsToJson`): settings as values and
 * every list as an array of objects. Only lists with records are included,
 * since importing an empty list clears it on the device.
 */
export function settingsDump(vault: Items): string {
  const dump: Record<string, unknown> = {};
  for (const item of vault.items("settings")) dump[item.id] = JSON.parse(item.value);
  for (const [collection, pref] of Object.entries(LIST_PREFS)) {
    const items = vault.items(collection);
    if (items.length) dump[pref] = items.map((item) => JSON.parse(item.value));
  }
  return JSON.stringify(dump);
}

/** A dictionary as the app's `.dic` file: one uppercase hex key per line. */
export const dictionaryFile = (dictionary: Dictionary) =>
  dictionary.keys
    .map((key) => `${key.map((b) => b.toString(16).padStart(2, "0")).join("").toUpperCase()}\n`)
    .join("");

/** Ids of a folder and all folders below it. */
function subtree(root: string, folders: Folder[]): Set<string> {
  const ids = new Set([root]);
  for (let grew = true; grew; ) {
    grew = false;
    for (const folder of folders) {
      if (folder.parentId && ids.has(folder.parentId) && !ids.has(folder.id)) {
        ids.add(folder.id);
        grew = true;
      }
    }
  }
  return ids;
}

/** A folder with everything in it, as the app's folder export (`CardFolderBundle` / `DictionaryFolderBundle`). */
export function folderBundle(kind: "cards" | "dictionaries", root: string, vault: Items): string {
  const folders = vault.items(kind === "cards" ? "card_folders" : "dictionary_folders").map((i) => parse<Folder>(i));
  const ids = subtree(root, folders);
  return JSON.stringify({
    format: kind === "cards" ? "chameleon-ultra-gui-folder" : "chameleon-ultra-gui-dictionary-folder",
    version: 1,
    rootFolderId: root,
    folders: folders.filter((folder) => ids.has(folder.id)),
    [kind]: vault
      .items(kind)
      .map((item) => parse<{ folderId?: string }>(item))
      .filter((value) => value.folderId !== undefined && ids.has(value.folderId)),
  });
}

/** Folders in tree order with their depth, for a picker. */
export function folderTree(folders: Folder[]): { folder: Folder; depth: number }[] {
  const ids = new Set(folders.map((f) => f.id));
  const out: { folder: Folder; depth: number }[] = [];
  const visit = (parent: string | undefined, depth: number) => {
    for (const folder of folders
      .filter((f) => (f.parentId && ids.has(f.parentId) ? f.parentId : undefined) === parent)
      .sort((a, b) => a.name.localeCompare(b.name))) {
      out.push({ folder, depth });
      if (depth < 32) visit(folder.id, depth + 1);
    }
  };
  visit(undefined, 0);
  return out;
}

/** A file name the app and every OS accept. */
export const fileName = (name: string, extension: string) =>
  `${name.replace(/[\\/:*?"<>|\u0000-\u001f]/g, "_").trim() || "export"}.${extension}`;

export function download(name: string, content: string, type = "application/json") {
  const url = URL.createObjectURL(new Blob([content], { type }));
  const link = Object.assign(document.createElement("a"), { href: url, download: name });
  link.click();
  URL.revokeObjectURL(url);
}
