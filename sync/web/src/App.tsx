import { type ReactNode, useCallback, useEffect, useRef, useState } from "react";
import { Api, SyncError } from "./api";
import {
  type Card,
  type Dictionary,
  dictionaryFile,
  download,
  type Folder,
  fileName,
  folderBundle,
  folderTree,
  parse,
  settingsDump,
  tagName,
} from "./cugui";
import { hlcDate } from "./hlc";
import { Icon, type IconName } from "./icons";
import { type Item, joinWithCode, type Session, sessionFromPhrase, Vault } from "./vault";

/** Where the API lives: next to this page, so the app also works under a path prefix. */
const BASE = new URL(".", location.href).pathname.replace(/\/$/, "");
const SESSION_KEY = "cu-sync-session";

function describe(error: unknown): string {
  if (!(error instanceof SyncError)) {
    return /mnemonic|checksum|word/i.test(String(error)) ? "This is not a valid recovery phrase." : String(error);
  }
  switch (error.code) {
    case "code":
      return "This is not a valid pairing code.";
    case "expired":
      return "The pairing code expired. Create a new one in the app.";
    case "changed":
      return "Another device changed this meanwhile. Try again to replace that change.";
    case "rate_limited":
      return "Too many requests. Try again in a minute.";
    case "too_large":
      return "This record is too large to sync.";
    case "unauthorized":
      return "No vault for this recovery phrase on this server.";
    case "not_found":
      return "The pairing code expired or belongs to another server.";
    default:
      return `Request failed (${error.code}).`;
  }
}

const storage = {
  load(): Session | null {
    try {
      return JSON.parse(localStorage.getItem(SESSION_KEY) ?? "null") as Session | null;
    } catch {
      return null;
    }
  },
  save(session: Session | null) {
    try {
      if (session) localStorage.setItem(SESSION_KEY, JSON.stringify(session));
      else localStorage.removeItem(SESSION_KEY);
    } catch {
      // Without storage the session lasts until the page closes.
    }
  },
};

export function App() {
  const [notice, setNotice] = useState<string>();
  const [vault, setVault] = useState<Vault | null>(null);
  const [message, setMessage] = useState<string>();
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    Api.info(BASE)
      .then((info) => setNotice(info.notice?.trim() || undefined))
      .catch(() => {});
    const saved = storage.load();
    if (!saved) return setLoading(false);
    Vault.open(saved, BASE)
      .then(setVault)
      .catch((error) => {
        if (error instanceof SyncError && error.status === 401) {
          storage.save(null);
          setMessage("This browser was removed from the vault.");
        } else {
          setMessage(describe(error));
        }
      })
      .finally(() => setLoading(false));
  }, []);

  const open = (next: Vault) => {
    // Paired browsers are devices and stay signed in; recovery phrase sessions end with the page.
    if (next.isDevice) storage.save(next.session);
    setMessage(undefined);
    setVault(next);
  };

  const signOut = async () => {
    if (vault?.isDevice) {
      if (!confirm("Remove this browser from the vault? You need a new pairing code to come back.")) return;
      try {
        await vault.leave();
      } catch {
        // Already removed, or offline: the app can still remove it.
      }
    }
    storage.save(null);
    setVault(null);
  };

  return (
    <div className="mx-auto max-w-5xl px-4 pb-10 sm:px-6">
      {message && (
        <div className="pt-4">
          <Banner onClose={() => setMessage(undefined)}>{message}</Banner>
        </div>
      )}
      {loading ? (
        <p className="py-10 text-center text-muted">Loading…</p>
      ) : vault ? (
        <Browser vault={vault} onSignOut={signOut} />
      ) : (
        <Login notice={notice} onOpen={open} />
      )}
    </div>
  );
}

function Banner({ children, onClose }: { children: ReactNode; onClose: () => void }) {
  return (
    <div role="alert" className="flex items-start gap-3 rounded-lg bg-accent/10 px-4 py-3 text-sm">
      <span className="grow">{children}</span>
      <button type="button" onClick={onClose} className="text-muted hover:text-fg" aria-label="Dismiss">
        ✕
      </button>
    </div>
  );
}

// --- sign in ------------------------------------------------------------------

function Login({ notice, onOpen }: { notice?: string; onOpen: (vault: Vault) => void }) {
  const [mode, setMode] = useState<"phrase" | "pair">("phrase");
  const [phrase, setPhrase] = useState("");
  const [code, setCode] = useState("");
  const [name, setName] = useState("Web browser");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string>();
  const [waiting, setWaiting] = useState<string>();
  const abort = useRef<AbortController | null>(null);

  useEffect(() => () => abort.current?.abort(), []);

  const run = async (action: () => Promise<Vault>) => {
    setBusy(true);
    setError(undefined);
    try {
      onOpen(await action());
    } catch (e) {
      if (!(e instanceof SyncError && e.code === "cancelled")) setError(describe(e));
    } finally {
      setBusy(false);
      setWaiting(undefined);
    }
  };

  const submit = (event: React.FormEvent) => {
    event.preventDefault();
    if (mode === "phrase") {
      void run(() => Vault.open(sessionFromPhrase(phrase), BASE));
      return;
    }
    abort.current = new AbortController();
    const signal = abort.current.signal;
    void run(async () => Vault.open(await joinWithCode(code, name.trim() || "Web browser", BASE, setWaiting, signal), BASE));
  };

  return (
    <main className="mx-auto w-full max-w-lg space-y-4 pt-10 sm:pt-16">
      <div className="flex flex-col items-center gap-3 pb-2 text-center">
        <img src="./logo.png" alt="" className="size-16 rounded-2xl" />
        <h1 className="text-xl font-semibold">Chameleon Ultra GUI Sync Server</h1>
      </div>
      {notice && (
        <section className="rounded-xl border border-line p-4">
          <h2 className="mb-1 text-sm font-semibold">Notice from this server</h2>
          <p className="whitespace-pre-wrap text-sm text-muted">{notice}</p>
        </section>
      )}
      <form onSubmit={submit} className="space-y-4 rounded-xl border border-line p-5">
        <p className="text-sm text-muted">
          Browse and edit the cards, dictionaries and settings in your vault. Everything is decrypted in this page; the
          server only sees ciphertext.
        </p>
        <div className="grid grid-cols-2 gap-1 rounded-lg bg-surface p-1 text-sm" role="tablist">
          {(["phrase", "pair"] as const).map((m) => (
            <button
              key={m}
              type="button"
              role="tab"
              aria-selected={mode === m}
              disabled={busy}
              onClick={() => setMode(m)}
              className={`rounded-md px-3 py-1.5 ${mode === m ? "bg-bg font-medium shadow-sm" : "text-muted"}`}
            >
              {m === "phrase" ? "Recovery phrase" : "Pairing code"}
            </button>
          ))}
        </div>
        {mode === "phrase" ? (
          <Field label="Recovery phrase" hint="Nothing is stored: signing in again needs the phrase.">
            <textarea
              value={phrase}
              onChange={(e) => setPhrase(e.target.value)}
              rows={3}
              required
              autoComplete="off"
              autoCapitalize="none"
              spellCheck={false}
              className="input font-mono"
            />
          </Field>
        ) : (
          <>
            <Field label="Pairing code" hint="In the app: Settings → Sync → Add device. This browser becomes a device.">
              <textarea
                value={code}
                onChange={(e) => setCode(e.target.value)}
                rows={3}
                required
                spellCheck={false}
                className="input font-mono text-xs"
              />
            </Field>
            <Field label="Name of this browser">
              <input value={name} onChange={(e) => setName(e.target.value)} maxLength={64} className="input" />
            </Field>
          </>
        )}
        {waiting && (
          <div className="rounded-lg bg-surface p-3 text-sm">
            Approve the request in the app if it shows this code:
            <div className="mt-1 font-mono text-lg font-semibold tracking-wider">{waiting}</div>
          </div>
        )}
        {error && <p className="text-sm text-danger">{error}</p>}
        <div className="flex justify-end gap-2">
          {waiting && (
            <button type="button" className="button" onClick={() => abort.current?.abort()}>
              Cancel
            </button>
          )}
          <button type="submit" disabled={busy} className="button-primary">
            {busy ? (waiting ? "Waiting for approval…" : "Opening…") : mode === "phrase" ? "Open vault" : "Join"}
          </button>
        </div>
      </form>
    </main>
  );
}

function Field({ label, hint, children }: { label: string; hint?: string; children: ReactNode }) {
  return (
    <label className="block space-y-1.5">
      <span className="text-sm font-medium">{label}</span>
      {children}
      {hint && <span className="block text-xs text-muted">{hint}</span>}
    </label>
  );
}

// --- browsing -------------------------------------------------------------------

/** One row: what it shows and what can be done with it. */
type Row = {
  item: Item;
  icon: IconName;
  /** The item's own color (`#RRGGBB`), if it has one. */
  color?: string;
  title: string;
  detail: string;
  /** File name and content of a single-item export. */
  file?: [name: string, content: string, type?: string];
};

type TabId = "cards" | "dictionaries" | "folders" | "settings" | "plugins" | "devices";

const TABS: { id: TabId; label: string; collections: string[]; readOnly?: boolean }[] = [
  { id: "cards", label: "Cards", collections: ["cards"] },
  { id: "dictionaries", label: "Dictionaries", collections: ["dictionaries"] },
  { id: "folders", label: "Folders", collections: ["card_folders", "dictionary_folders"] },
  { id: "settings", label: "Settings", collections: ["settings"] },
  { id: "plugins", label: "Plugins", collections: ["plugins"] },
  { id: "devices", label: "Devices", collections: ["_devices"], readOnly: true },
];

function toRow(item: Item, self: string): Row {
  const value = parse<Record<string, unknown>>(item);
  const name = typeof value?.name === "string" && value.name ? value.name : item.id;
  // The app stores colors as `#RRGGBB`.
  const color = typeof value?.color === "string" && /^#[0-9a-f]{6}$/i.test(value.color) ? value.color : undefined;
  switch (item.collection) {
    case "cards": {
      const card = value as Card;
      return {
        item,
        icon: "card",
        title: name,
        detail: [tagName(card.tag), card.uid].filter(Boolean).join(" - "),
        color,
        file: [fileName(name, "json"), item.value],
      };
    }
    case "dictionaries": {
      const dictionary = value as Dictionary;
      const keys = Array.isArray(dictionary.keys) ? dictionary.keys.length : 0;
      return {
        item,
        icon: "key",
        title: name,
        detail: `${keys} key${keys === 1 ? "" : "s"}`,
        color,
        file: [fileName(name, "dic"), dictionaryFile(dictionary), "text/plain"],
      };
    }
    case "settings":
      return { item, icon: "tune", title: item.id, detail: item.value };
    case "_devices": {
      const added = typeof value.added === "string" ? new Date(value.added).toLocaleDateString() : "";
      return { item, icon: "devices", title: name, detail: [item.id === self ? "This browser" : "", added && `Added ${added}`].filter(Boolean).join(" - ") };
    }
    default:
      return {
        item,
        icon: item.collection === "plugins" ? "extension" : "folder",
        title: name,
        detail: item.collection === "card_folders" ? "Card folder" : item.collection === "dictionary_folders" ? "Dictionary folder" : "",
        color,
        file: [fileName(name, "json"), item.value],
      };
  }
}

function Browser({ vault, onSignOut }: { vault: Vault; onSignOut: () => void }) {
  const [tab, setTab] = useState<TabId>("cards");
  const [query, setQuery] = useState("");
  const [folder, setFolder] = useState("");
  const [editing, setEditing] = useState<Item | null>(null);
  const [error, setError] = useState<string>();
  const [busy, setBusy] = useState(false);
  // Bumped after every pull or write: the vault is mutable state outside React.
  const [, setVersion] = useState(0);

  /** Runs a vault action; returns its error message, if any. */
  const act = useCallback(async (action: () => Promise<void>) => {
    setBusy(true);
    setError(undefined);
    try {
      await action();
    } catch (e) {
      return describe(e);
    } finally {
      setBusy(false);
      setVersion((v) => v + 1);
    }
  }, []);
  const report = (result: Promise<string | undefined>) => void result.then(setError);

  const refresh = useCallback(() => act(() => vault.refresh()).then(setError), [act, vault]);

  useEffect(() => {
    const onFocus = () => document.visibilityState === "visible" && void refresh();
    document.addEventListener("visibilitychange", onFocus);
    return () => document.removeEventListener("visibilitychange", onFocus);
  }, [refresh]);

  const current = TABS.find((t) => t.id === tab)!;
  const folderKind = tab === "cards" || tab === "dictionaries" ? tab : null;
  // Recomputed every render (setVersion triggers one after vault changes); vaults are small.
  const folders = folderKind
    ? folderTree(vault.items(folderKind === "cards" ? "card_folders" : "dictionary_folders").map((i) => parse<Folder>(i)))
    : [];
  const needle = query.trim().toLowerCase();
  const rows = current.collections
    .flatMap((collection) => vault.items(collection))
    .map((item) => toRow(item, vault.session.memberId))
    .filter((row) => !folder || parse<{ folderId?: string }>(row.item).folderId === folder)
    .filter((row) => !needle || `${row.title} ${row.detail}`.toLowerCase().includes(needle))
    .sort((a, b) => a.title.localeCompare(b.title));

  const count = (collections: string[]) => collections.reduce((n, c) => n + vault.items(c).length, 0);

  const remove = (row: Row) => {
    if (confirm(`Delete “${row.title}” on all devices?`)) report(act(() => vault.write(row.item.collection, row.item.id, null)));
  };

  return (
    <main className="space-y-4">
      <header className="flex flex-wrap items-center gap-x-3 gap-y-3 border-b border-line py-4">
        <img src="./logo.png" alt="" className="size-9 rounded-lg" />
        <div className="mr-auto min-w-0">
          <h1 className="truncate font-semibold leading-tight">Chameleon Ultra GUI Sync Server</h1>
          <p className="truncate text-xs text-muted">
            {vault.isDevice ? "Signed in as a paired device" : "Signed in with the recovery phrase"}
          </p>
        </div>
        <div className="flex gap-2">
          <button type="button" className="button" onClick={refresh} disabled={busy}>
          Refresh
        </button>
        <button
          type="button"
          className="button"
          onClick={() => download("ChameleonUltraGUISettings.json", settingsDump(vault))}
          title="Everything synced, as the app's settings export (Settings → Import settings)"
        >
          Export all
        </button>
          <button type="button" className="button" onClick={onSignOut}>
            Sign out
          </button>
        </div>
      </header>

      <nav className="-mx-1 flex gap-1 overflow-x-auto border-b border-line px-1" role="tablist">
        {TABS.map((t) => (
          <button
            key={t.id}
            type="button"
            role="tab"
            aria-selected={tab === t.id}
            onClick={() => {
              setTab(t.id);
              setFolder("");
            }}
            className={`-mb-px whitespace-nowrap border-b-2 px-3 py-2 text-sm ${
              tab === t.id ? "border-accent font-medium" : "border-transparent text-muted hover:text-fg"
            }`}
          >
            {t.label} <span className="text-xs text-muted">{count(t.collections)}</span>
          </button>
        ))}
      </nav>

      <div className="flex flex-wrap gap-2">
        <input
          type="search"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search"
          className="input min-w-0 flex-1 basis-48"
        />
        {folderKind && folders.length > 0 && (
          <>
            <select value={folder} onChange={(e) => setFolder(e.target.value)} className="input w-auto max-w-full">
              <option value="">All folders</option>
              {folders.map(({ folder: f, depth }) => (
                <option key={f.id} value={f.id}>
                  {"  ".repeat(depth) + f.name}
                </option>
              ))}
            </select>
            {folder && (
              <button
                type="button"
                className="button"
                title="Everything in this folder, as the app's folder export"
                onClick={() => {
                  const name = folders.find((f) => f.folder.id === folder)?.folder.name ?? "folder";
                  download(fileName(name, "json"), folderBundle(folderKind, folder, vault));
                }}
              >
                Export folder
              </button>
            )}
          </>
        )}
      </div>

      {error && <p className="text-sm text-danger">{error}</p>}

      {rows.length === 0 ? (
        <p className="py-10 text-center text-sm text-muted">Nothing here.</p>
      ) : (
        <ul className="divide-y divide-line rounded-xl border border-line">
          {rows.map((row) => (
            <li key={`${row.item.collection}/${row.item.id}`} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-4 py-3">
              <Icon name={row.icon} color={row.color} className="text-muted" />
              <div className="min-w-0 flex-1 basis-56">
                <div className="truncate font-medium">{row.title}</div>
                <div className="truncate text-xs text-muted">
                  {row.detail}
                  {row.detail && " - "}
                  <time>{hlcDate(row.item.time)?.toLocaleString() ?? "before sync"}</time>
                </div>
              </div>
              <div className="ml-8 flex gap-1 sm:ml-0">
                {row.file && (
                  <button type="button" className="button-small" onClick={() => download(...row.file!)}>
                    Export
                  </button>
                )}
                {!current.readOnly && (
                  <>
                    <button type="button" className="button-small" onClick={() => setEditing(row.item)}>
                      Edit
                    </button>
                    <button type="button" className="button-small text-danger" disabled={busy} onClick={() => remove(row)}>
                      Delete
                    </button>
                  </>
                )}
              </div>
            </li>
          ))}
        </ul>
      )}

      {editing && (
        <Editor
          item={editing}
          onClose={() => setEditing(null)}
          onSave={async (value) => {
            const failed = await act(() => vault.write(editing.collection, editing.id, value));
            if (!failed) setEditing(null);
            return failed;
          }}
        />
      )}
    </main>
  );
}

/** Edits a record's JSON. Settings are plain values; list records must keep their `id`. */
function Editor({
  item,
  onClose,
  onSave,
}: {
  item: Item;
  onClose: () => void;
  /** Resolves to an error message when saving failed. */
  onSave: (value: string) => Promise<string | undefined>;
}) {
  const dialog = useRef<HTMLDialogElement>(null);
  const [text, setText] = useState(() => JSON.stringify(JSON.parse(item.value), null, 2));
  const [error, setError] = useState<string>();

  useEffect(() => dialog.current?.showModal(), []);

  const save = (event: React.FormEvent) => {
    event.preventDefault();
    let value: unknown;
    try {
      value = JSON.parse(text);
    } catch (e) {
      return setError(`Not valid JSON: ${(e as Error).message}`);
    }
    if (item.collection === "settings") {
      if (!["boolean", "number", "string"].includes(typeof value)) return setError("A setting is a number, string or boolean.");
    } else if (typeof value !== "object" || value === null || Array.isArray(value)) {
      return setError("This must be a JSON object.");
    } else if ((value as { id?: unknown }).id !== item.id) {
      return setError(`The id must stay "${item.id}".`);
    }
    void onSave(JSON.stringify(value)).then(setError);
  };

  return (
    <dialog
      ref={dialog}
      onClose={onClose}
      className="m-auto w-[min(48rem,calc(100vw-2rem))] rounded-xl bg-bg p-0 text-fg backdrop:bg-black/40"
    >
      <form onSubmit={save} className="flex max-h-[85dvh] flex-col gap-3 p-5">
        <h2 className="font-semibold">
          Edit {toRow(item, "").title}
        </h2>
        <textarea
          value={text}
          onChange={(e) => setText(e.target.value)}
          spellCheck={false}
          className="input min-h-64 grow font-mono text-xs"
        />
        {error && <p className="text-sm text-danger">{error}</p>}
        <div className="flex justify-end gap-2">
          <button type="button" className="button" onClick={() => dialog.current?.close()}>
            Cancel
          </button>
          <button type="submit" className="button-primary">
            Save
          </button>
        </div>
      </form>
    </dialog>
  );
}
