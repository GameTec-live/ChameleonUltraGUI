# Small plugin examples

Import any `.plugin.json` file using **Plugins → Import**. All examples work
without a connected device. Open **Edit** to inspect their Lua source and
resources before running them.

| Plugin | Demonstrates | Effect |
| --- | --- | --- |
| [Count saved cards](saved-card-count.plugin.json) | `cards.list`, `ui.info` | Displays a count |
| [Toggle theme](toggle-theme.plugin.json) | `settings.get`, `settings.update`, `ui.snackbar` | Changes light/dark mode |
| [Choose language](choose-language.plugin.json) | `settings.options`, choice input | Changes GUI language |
| [Create dictionary](create-dictionary.plugin.json) | Text resources, dictionary decoding and saving | Creates a new two-key dictionary on every run |
| [Offline nested recovery](offline-nested.plugin.json) | Standalone native recovery | Calculates keys from a fixed test capture |

The recovery example requires the native recovery library included in normal
app builds. Changes to language and theme persist and can also be reversed in
Settings. The dictionary can be deleted from Saved Cards.

## Writing your own

A minimal saved-data flow:

```lua
local folder = chameleon.cardFolders.save({name = "My tools"})
local card = chameleon.cards.list()[1]
if card ~= nil then chameleon.cards.move(card.id, folder) end
```

Only run this if you want to create that folder and move the first card.
The full [API reference](../../plugins.md) documents table schemas, folder
imports/exports, GUI preferences and the inputs for each recovery algorithm.
