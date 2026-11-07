# Writing plugins in VS Code

Use the [Lua API reference](../plugins.md) for runtime behavior and hardware
requirements. The GUI runs LuaLike, not a local Lua interpreter. You can edit,
check and bundle a plugin without connecting a device.

## Create a project

1. Install [VS Code](https://code.visualstudio.com/),
   [Lua by LuaLS](https://marketplace.visualstudio.com/items?itemName=sumneko.lua),
   Node.js 22 or newer and Git.
2. Copy the contents of [development/](development/) (including hidden files)
   into a new plugin folder. The bundler and VS Code build task are included.
   Open this folder itself in VS Code with **File → Open Folder**.
3. Run `git init` in its terminal (unnecessary if already inside a repository).
4. Edit `plugin.config.json` to set your plugin name and description, then edit
   `main.lua`. Type `chameleon.` or `chameleon.device.` to see completions;
   hover a function for its parameters and return type. **Ctrl+Space** opens
   suggestions and **Ctrl+Shift+Space** opens signature help.

The template's `.luarc.json` loads `types/chameleon.d.lua` as an editor library.
It declares every GUI host function, resource/codec function, enum string and
structured result. It does not need a `require` or a globals suppression list.
These declarations are editor metadata: never load them at runtime. Update the
types from this repository when updating the GUI. LuaLS configuration and
annotations are documented in the [LuaLS settings](https://luals.github.io/wiki/settings/)
and [annotation reference](https://luals.github.io/wiki/annotations/).

The Lua 5.4 setting supplies an editor baseline; it does not promise full PUC Lua
compatibility. The template disables completion for unavailable ambient libraries.
The GUI's additional LuaLike `convert` and `crypto` libraries are outside these
GUI API declarations. Calls use dots (`chameleon.ui.info(...)`), not colons.
Byte buffers are integer arrays and use Lua's 1-based indexing. Hardware slots
and blocks keep their 0-based numbering. A saved card's `tag` is numeric;
communicator enum arguments are strings, such as `"mifare1K"`.

## Build and import

Run **Terminal → Run Build Task** (**Ctrl+Shift+B**, **Cmd+Shift+B** on macOS),
or run this in the plugin folder:

```sh
node build-plugin.js
```

From elsewhere, pass the folder: `node /path/to/build-plugin.js /path/to/plugin`.
No npm install is needed. The default output is `dist/plugin.plugin.json`.
Import it using **Tools → Plugins → Import** in the GUI, review it, then tap its
card to run it. Reimporting creates a new local plugin identity.

`plugin.config.json` accepts `name` (required), `description` (default empty),
`color` (unsigned 32-bit ARGB integer, default orange), `id` (optional string;
otherwise a UUID is generated per build), `output` (relative to the plugin
folder, default `dist/plugin.plugin.json`), and `compress` (default false).
Set `compress` to true to gzip and base64 the code/resources payload using the
GUI's portable format. The bundler enforces the GUI's 8 MiB payload and 16 MiB
envelope limits before writing.

## Resources and Git ignores

`main.lua` becomes the plugin code. Every other regular file is a resource,
recursively, using a forward-slash path relative to the plugin folder as its
exact key. The bundler excludes itself, `plugin.config.json`, the current output
file and Git metadata. Symlinks are skipped. Git's ignore rules apply even to
tracked files; nested `.gitignore` rules, negations and repository/global
excludes are handled by Git itself. Nested repositories and checked-out submodules
are included using their own ignore rules; their Git metadata is excluded.

The template's `.gitignore` excludes editor configuration, declarations, itself
and `dist/` from the bundle. **Git also hides those files from `git add`**: to
version your setup, explicitly force-add `.gitignore`, `.luarc.json`, `.vscode/`
and `types/`. Keep build outputs ignored. If you customize the output path,
ignore its directory to avoid bundling older artifacts under other names.

For example, create `helpers.lua` and `assets/message.txt` beside `main.lua`:

```lua
-- helpers.lua
return { greeting = "Hello" }
```

```lua
-- main.lua
local helpers = require("helpers.lua")
local message = chameleon.resources.get("assets/message.txt")
chameleon.ui.info(helpers.greeting .. ": " .. message)
```

`require` takes the exact resource key, including `.lua`; it does not search
Lua package paths. Modules are evaluated once per invocation. LuaLS's `runtime.path`
is set to `?` with `completion.requireSeparator` set to `/` so these literal
resource names can resolve in the editor too.

Valid UTF-8 resources are preserved as text. Files containing invalid UTF-8
are stored as base64; read them with
`chameleon.codec.base64DecodeBytes(chameleon.resources.get("assets/image.png"))`.
For binary data that happens to be valid UTF-8, store a base64 text file yourself
and decode it the same way. No decoding happens automatically in the GUI.
