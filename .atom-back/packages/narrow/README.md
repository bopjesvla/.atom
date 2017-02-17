# narrow

narrow something.  
Code navigation tool inspired by unite.vim, emacs-helm.  

# Development status

alpha

![narrow](https://raw.githubusercontent.com/t9md/t9md/4df5df86884a25bf8b62dc3b605df050a06c8232/img/atom-narrow/narrow.gif)

# What's this

- Provide narrowing UI like unite/denite.vim or emacs-helm.
- But **not** aiming to become "can open anything from narrow-able UI" package.
- Primal focus is on **code-navigation**.
- Most of bundled providers are **bound to specific editor**.
- And sync current-item on narrow-UI as you move cursor on bound editor.
- This **auto sync current-item to cursor of bound editor** gives you valuable context to keep focus on X.  

# Roles in play.

- `narrow-editor` or `narrow-ui`: handles user input and update narrowed item list.
- `narrow-provider`: Provide items to narrow and action to jump to item selected.

![overview](https://raw.githubusercontent.com/t9md/t9md/45e8b52a2fbe8a9d47a2f2d30e8f755f5d5cba25/img/atom-narrow/narrow-overview.png)

# Features

- Auto preview items under cursor(default `true` for all providers).
- Auto update items on narrow-editor when item changed(e.g. `narrow:lines` refresh items when text changed).
- Auto refresh items on active text-editor change(e.g. `narrow:symbols` always shows current-editor's symbol list).
- Auto sync editor's cursor position to selected item on narrow-editor(narrowing UI).
- Navigate between narrowed items without focusing narrow-editor.
- Direct edit in narrow-editor which update realFile on disk by `narrow:update-real-file` commands.
- [vim-mode-plus](https://atom.io/packages/vim-mode-plus) integration( I'm also maintainer of vim-mode-plus ).
- For what can I use this?, See [Use case and flow of keystrokes](https://github.com/t9md/atom-narrow/issues/75).
- Also see [Q&A](#qa) section at bottom of this README.

# Bundled providers

- `search`: Search by `ag`( you need to install `ag` by yourself).
- `atom-scan`: Similar to `search` but use Atom's `atom.workspace.scan`.
- `lines`: Narrow current editors lines.
- `scan`: Scan current editor by `TextEditor.prototype.scan`. created for better replacement of `narrow:lines`.
- `fold`: Provide fold-starting rows as item.
- `git-diff`: Info source is from core `git-diff` package.
- `bookmarks`: For core `bookmarks` package
- `symbols`: Symbols are provided by core `symbols-views` package's.
- `linter`: Use message provided by [linter](https://atom.io/packages/linter) package.

# Quick tour

To follow this quick-tour, you don't need custom keymap.

### Step1. basic by using `narrow:lines`

Items are each lines on editor.

1. Open some text-editor, then via command-palette, invoke `Narrow Line`.
2. narrow-editor opened, as you type, you can narrow items.
3. When you type `apple lemon` as query. lines which matched both `apple` and `lemon` are listed.
4. You can move normal `up`, `down`(or `j`, `k` in read-only mode) key to quick-preview items.
5. `enter` to confirm. When confirmed, narrow-editor closed.

The read-only mode is enabled by default.

### Step2. navigate from outside of `narrow-editor`.

1. Open some text-editor, then via command-palette, invoke `Narrow Line`.
2. narrow-editor opened, as you type, you can narrow items.
3. Click invoking editor. And see your clicked position is auto reflected narrow-editor.
4. `ctrl-cmd-n` to move to `next-item`, `ctrl-cmd-p` to move to `previous-item`.
5. If you want to close narrow-editor you can close by `ctrl-g`(no need to focus narrow-editor).
6. If you want to change narrow-query, you have to focus to narrow-editor
  - Use `ctrl-cmd-f`(`narrow:focus`) to focus narrow-editor's item indicator row.
  - Use `ctrl-cmd-i`(`narrow:focus-prompt`) to focus narrow-editor's query prompt row
  - Both commands are available from outside/inside of narrow-editor.
7. These navigation keymaps are available for all provider(e.g. `search`, `fold` etc).

### Step3. [DANGER] direct-edit

Direct-edit is "edit on narrow-editor then save to real-file" feature.  
Available for these three providers `lines`, `search` and `atom-scan`.  

⚠️ This feature is really new and still experimental state.  
⚠️ Don't try code-base which is not managed by SCM.  
⚠️ I can say sorry, but I can not recover file for you.  

1. Open file from project, place cursor for variable name `hello`
2. Then invoke `Narrow Search By Current Word`.
3. All `hello` matching items are shows up on narrow-editor.
4. If you want, you can further narrow by query.
5. Then edit narrow-editor's text **directly**.
  - Place cursor on `hello`. Then `ctrl-cmd-g`(`find-and-replace:select-all`), then type `world`.
6. Invoke `Narrow Ui: Update Real File` from command-palette.
7. DONE, changes you made on narrow-editor items are applied to real-file(and saved).
8. You can undo changes by re-edit items on narrow-editor and reapply changes by `Narrow Ui: Update Real File`.


# Commands

### Available in all text-editor

##### Ohters

- `narrow:focus`: ( `ctrl-cmd-f` ) Focus to `narrow-editor`, if executed in `narrow-editor`, it re-focus to original editor.
- `narrow:focus-prompt`: ( `ctrl-cmd-i` ) Focus to `narrow-editor`'s query input prompt, if executed in `narrow-editor`, it re-focus to original editor.
- `narrow:refresh`: Manually refresh items in `narrow-editor`.
- `narrow:close`: ( `ctrl-g` ) Close currently opened `narrow-editor` one at a time.
- `narrow:next-item`: ( `ctrl-cmd-n` ) Move cursor to position of next-item.
- `narrow:previous-item`: ( `ctrl-cmd-p` ) Move cursor to position of previous-item.

##### Provider commands

No keymaps are provided

- `narrow:lines`
- `narrow:lines-by-current-word`
- `narrow:scan`
- `narrow:scan-by-current-word`
- `narrow:fold`
- `narrow:fold-by-current-word`
- `narrow:search`: [ag](https://github.com/ggreer/the_silver_searcher) search. need install by your self.
- `narrow:search-by-current-word`
- `narrow:search-current-project`
- `narrow:search-current-project-by-current-word`
- `narrow:atom-scan`
- `narrow:atom-scan-by-current-word`
- `narrow:focus`
- `narrow:symbols`
- `narrow:linter`
- `narrow:bookmarks`
- `narrow:git-diff`

### narrow-editor(narrow-ui)

- `core:confirm`: ( `enter` ) Close `narrow-editor`
- `narrow-ui:confirm-keep-open`: keep open `narrow-editor`
- `narrow-ui:preview-item`: Preview currently selected item manually( you don't need in most case ).
- `narrow-ui:preview-next-item`: ( `tab` ) Preview next-item without moving cursor from `narrow-editor`'s query prompt.
- `narrow-ui:preview-previous-item`: ( `shift-tab` ) Preview next-item without moving cursor from `narrow-editor`'s query prompt.
- `narrow-ui:toggle-auto-preview`: ( `ctrl-r` for non-vim-mode-plus user) Disable/enable auto-preview for this `narrow-editor`.
<!-- - `narrow-ui:move-to-prompt-or-selected-item`: ( DEPRECATED ) -->
- `narrow-ui:move-to-prompt`: `ctrl-cmd-i`
- `narrow-ui:start-insert`: `I`, `a`
- `narrow-ui:stop-insert`: `escape`
- `narrow-ui:update-real-file`: Apply changes made in `narrow-editor` to real-file.( edit in `narrow-editor` then save it to real file. )

# Keymaps

No keymap to invoke narrow provider(e.g `narrow:lines`).  
Start it from command-palette or set keymap in `keymap.cson`.

⚠️ [default keymap](https://github.com/t9md/atom-narrow/blob/master/keymaps/narrow.cson) is not yet settled, this will likely to change in future version.   

### My keymap(vim-mode-plus user) and config


I set `closeOnConfirm` to `false` for all provider.  
Since I want to close manually by `ctrl-g`(Maybe change default in future).  

###### config

```
  narrow:
    AtomScan:
      closeOnConfirm: false
    Bookmarks:
      closeOnConfirm: false
    Fold:
      closeOnConfirm: false
    GitDiff:
      closeOnConfirm: false
    Lines:
      closeOnConfirm: false
    Linter:
      closeOnConfirm: false
    Scan:
      closeOnConfirm: false
    Search:
      closeOnConfirm: false
    Symbols:
      closeOnConfirm: false
    confirmOnUpdateRealFile: false
```

###### `keymap.cson`

```coffeescript
# From outside of narrow-editor
# -------------------------
'atom-text-editor.vim-mode-plus.normal-mode':
  'space f': 'narrow:fold'
  'space o': 'narrow:symbols'

  'space l': 'narrow:scan'
  'space L': 'narrow:scan-by-current-word'
  # 'space l': 'narrow:lines'
  # 'space L': 'narrow:lines-by-current-word'
  'space c': 'narrow:linter'
  'space s': 'narrow:search'
  'space S': 'narrow:search-by-current-word'
  'space a': 'narrow:atom-scan'
  'space A': 'narrow:atom-scan-by-current-word'
  'space G': 'narrow:git-diff'
  'space B': 'narrow:bookmarks'

# Only on narrow-editor
# -------------------------
# - Use these TWO key very frequently
#   - cmd-f: To focus to narrow-editor AND focus-back to original-editor
#   - cmd-i: To focus to narrow-editor's prompt AND focus-back to original-editor

# When workspace has narrow-editor
'atom-workspace.has-narrow atom-text-editor.vim-mode-plus.normal-mode':
  'cmd-f': 'narrow:focus' # focus to narrow-editor
  'cmd-i': 'narrow:focus-prompt' # focus to prompt of narrow-editor
  'ctrl-cmd-l': 'narrow:refresh' # manually refresh items
  'down': 'narrow:next-item'
  'up': 'narrow:previous-item'

# narrow-editor regardless of mode of vim
'atom-text-editor.narrow.narrow-editor[data-grammar="source narrow"]':
  'cmd-f': 'narrow:focus'
  'cmd-i': 'narrow:focus-prompt' # cmd-i to return to calling editor.
  # Danger: apply change on narrow-editor to real file by `cmd-s`.
  'cmd-s': 'narrow-ui:update-real-file'

'atom-text-editor.narrow.narrow-editor.vim-mode-plus.normal-mode[data-grammar="source narrow"]':
  # Danger: I use direct-edit very frequently, so intentionally recover `i` of vim-mode-plus.
  'i': 'vim-mode-plus:activate-insert-mode'

# NOTE: following keymap prevent me to type `;`, `[`, `]` in insert-mode.
# Which is very problematic in direct-edit mode since I can not insert these chars.
# Be aware this limitation if you copy this.
# Solution comes in future by differentiating scope in prompt and item-area.
'atom-text-editor.narrow.narrow-editor.vim-mode-plus.normal-mode[data-grammar="source narrow"],
atom-text-editor.narrow.narrow-editor.vim-mode-plus.insert-mode[data-grammar="source narrow"]':
  ';': 'core:confirm' # Confirm by `;`
  ']': 'narrow-ui:preview-next-item' # preview next while cursor is at prompt
  '[': 'narrow-ui:preview-previous-item' # preview previous while cursor is at prompt
```

# Recommended configuration for other packages.

- Suppress autocomplete-plus's popup on narrow-editor
- Disable vim-mode-plus's highlight-search on narrow-editor

```coffeescript
"*":
  "autocomplete-plus":
    suppressActivationForEditorClasses: [
      # snip
      "narrow"
    ]
  # snip
  "vim-mode-plus":
    highlightSearchExcludeScopes: [
      "narrow"
    ]
```

# Notes for vim-mode-plus user

Learn [keymap](https://github.com/t9md/atom-narrow/blob/make-it-stable/keymaps/narrow.cson) available as default.  
e.g. You can move to next or previous item by `tab`, `shift-tab`(for this to work, you need vim-mode-plus v0.81.0 or later).  

## Start narrow from vim-mode-plus's search-input-form

If you are [vim-mode-plus](https://atom.io/packages/vim-mode-plus) user.
Following command are available from vim-mode-plus's search(`/` or `?`) mini-editor.
See [keymap definition](https://github.com/t9md/atom-narrow/blob/make-it-stable/keymaps/narrow.cson)

- `vim-mode-plus-user:narrow:lines`
- `vim-mode-plus-user:narrow:search`
- `vim-mode-plus-user:narrow:atom-scan`
- `vim-mode-plus-user:narrow:search-current-project`

## How to edit item-area for direct-edit.

- In narrow-editor, `i`, `a` in `normal-mode` move cursor to prompt line.
- So when you want to edit items itself for `direct-edit` and `update-real-file` use other key to enter `insert-mode`.
- `I` is intentionally mapped to `vim-mode-plus:activate-insert-mode` which is normally mapped to `i`.
  - Which might not be intuitive, but I want make item mutatation bit difficult. So user have to type `I`.
- Other than `I`, you can start `insert-mode` by `A`, `c` etc..

# Q&A

### How can I exclude particular file from `narrow:search`

- Use `backspace` to exclude particular file from result.
- `ctrl-backspace` clear excluded file list and refresh
- These keymaps are available in `narrow-editor` and you are in `read-only-mode`

### Want to skip to `next-file`, `previous-file`

- Use `n`, `p` in `read-only` mode.

### I want `narrow:symbols` always shows up at right-most pane and don't want to close.

1. Open `narrow:symbols`( or maybe you want to use `narrow:fold` )
2. Move this `narrow-editor` by drag and drop to the place where you want.
3. From command-palette, execute `Narrow Ui: Protect`. Now `narrow-editor` protected.
4. Protected `narrow-editor` is not closed by `ctrl-g`( `narrow:close` ), and not closed by confirm by `enter`.
5. To close, use normal `cmd-w` or close button on tab.
