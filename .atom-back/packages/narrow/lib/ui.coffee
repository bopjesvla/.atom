_ = require 'underscore-plus'
{Point, Range, CompositeDisposable, Emitter, Disposable} = require 'atom'
{
  activatePaneItemInAdjacentPane
  isActiveEditor
  getValidIndexForList
  setBufferRow
  isTextEditor
  isNarrowEditor
  paneForItem
} = require './utils'
settings = require './settings'
Grammar = require './grammar'
getFilterSpecForQuery = require './get-filter-spec-for-query'
Highlighter = require './highlighter'
ItemIndicator = require './item-indicator'
ProviderPanel = require './provider-panel'

module.exports =
class UI
  # UI static
  # -------------------------
  @uiByEditor: new Map()
  @unregister: (ui) ->
    @uiByEditor.delete(ui.editor)
    @updateWorkspaceClassList()

  @register: (ui) ->
    @uiByEditor.set(ui.editor, ui)
    @updateWorkspaceClassList()

  @get: (editor) ->
    @uiByEditor.get(editor)

  @updateWorkspaceClassList: ->
    atom.views.getView(atom.workspace).classList.toggle('has-narrow', @uiByEditor.size)

  # UI.prototype
  # -------------------------
  selectedItem: null
  previouslySelectedItem: null

  stopRefreshingDelay: 100
  stopRefreshingTimeout: null

  autoPreview: null
  autoPreviewOnQueryChange: null
  autoPreviewOnNextStopChanging: false
  syncingEditor: null

  preventAutoPreview: false
  preventSyncToEditor: false
  ignoreChange: false
  ignoreCursorMove: false
  destroyed: false
  items: []
  cachedItems: null # Used to cache result
  lastNarrowQuery: ''
  modifiedState: null
  readOnly: false
  protected: false
  excludedFiles: null

  isModified: ->
    @modifiedState

  setModifiedState: (state) ->
    if state isnt @modifiedState
      # HACK: overwrite TextBuffer:isModified to return static state.
      # This state is used for tabs package to show modified icon on tab.
      @modifiedState = state
      @editor.buffer.isModified = -> state
      @editor.buffer.emitModifiedStatusChanged(state)

  onDidMoveToPrompt: (fn) -> @emitter.on('did-move-to-prompt', fn)
  emitDidMoveToPrompt: -> @emitter.emit('did-move-to-prompt')

  onDidMoveToItemArea: (fn) -> @emitter.on('did-move-to-item-area', fn)
  emitDidMoveToItemArea: -> @emitter.emit('did-move-to-item-area')

  onDidRefresh: (fn) -> @emitter.on('did-refresh', fn)
  emitDidRefresh: -> @emitter.emit('did-refresh')
  onWillRefresh: (fn) -> @emitter.on('will-refresh', fn)
  emitWillRefresh: -> @emitter.emit('will-refresh')

  onDidChangeSelectedItem: (fn) -> @emitter.on('did-change-selected-item', fn)
  emitDidChangeSelectedItem: (event) -> @emitter.emit('did-change-selected-item', event)

  # 'did-stop-refreshing' event is debounced, fired after stopRefreshingDelay
  onDidStopRefreshing: (fn) -> @emitter.on('did-stop-refreshing', fn)
  emitDidStopRefreshing: ->
    clearTimeout(@stopRefreshingTimeout) if @stopRefreshingTimeout?
    stopRefreshingCallback = =>
      @stopRefreshingTimeout = null
      @emitter.emit('did-stop-refreshing')

    @stopRefreshingTimeout = setTimeout(stopRefreshingCallback, @stopRefreshingDelay)

  onDidPreview: (fn) -> @emitter.on('did-preview', fn)
  emitDidPreview: (event) -> @emitter.emit('did-preview', event)

  registerCommands: ->
    atom.commands.add @editorElement,
      'core:confirm': => @confirm()
      'narrow:close': (event) => @narrowClose(event)
      'narrow-ui:confirm-keep-open': => @confirm(keepOpen: true)
      'narrow-ui:protect': => @toggleProtect()
      'narrow-ui:preview-item': => @preview()
      'narrow-ui:preview-next-item': => @previewNextItem()
      'narrow-ui:preview-previous-item': => @previewPreviousItem()
      'narrow-ui:toggle-auto-preview': => @toggleAutoPreview()
      'narrow-ui:move-to-prompt-or-selected-item': => @moveToPromptOrSelectedItem()
      'narrow-ui:move-to-prompt': => @moveToPrompt()
      'narrow-ui:start-insert': => @setReadOnly(false)
      'narrow-ui:stop-insert': => @setReadOnly(true)
      'core:move-up': (event) => @moveUpOrDown(event, 'previous')
      'core:move-down': (event) => @moveUpOrDown(event, 'next')
      'narrow-ui:update-real-file': => @updateRealFile()
      'narrow-ui:exclude-file': => @excludeFile()
      'narrow-ui:clear-excluded-files': => @clearExcludedFiles()
      'narrow-ui:move-to-next-file-item': => @moveToNextFileItem()
      'narrow-ui:move-to-previous-file-item': => @moveToPreviousFileItem()
      'narrow-ui:toggle-search-whole-word': => @toggleSearchWholeWord()
      'narrow-ui:toggle-search-ignore-case': => @toggleSearchIgnoreCase()

  toggleSearchWholeWord: ->
    @provider.toggleSearchWholeWord()
    @refresh(force: true)
    @providerPanel.updateSearchOptionState()

  toggleSearchIgnoreCase: ->
    @provider.toggleSearchIgnoreCase()
    @refresh(force: true)
    @providerPanel.updateSearchOptionState()

  constructor: (@provider, {@input}={}) ->
    @disposables = new CompositeDisposable
    @emitter = new Emitter
    @excludedFiles = []
    @autoPreview = @provider.getConfig('autoPreview')
    @autoPreviewOnQueryChange = @provider.getConfig('autoPreviewOnQueryChange')
    @highlighter = new Highlighter(this) if @provider.useHighlighter

    # Special item used to translate narrow editor row to items without pain
    @promptItem = Object.freeze({_prompt: true, skip: true})
    @itemAreaStart = Object.freeze(new Point(1, 0))

    # Setup narrow-editor
    # -------------------------
    # Hide line number gutter for empty indent provider
    @editor = atom.workspace.buildTextEditor(lineNumberGutterVisible: @provider.indentTextForLineHeader)

    # FIXME
    # Opening multiple narrow-editor for same provider get title `undefined`
    # (e.g multiple narrow-editor for lines provider)
    providerDashName = @provider.getDashName()
    @editor.getTitle = -> providerDashName
    @editor.onDidDestroy(@destroy.bind(this))
    @editorElement = @editor.element
    @editorElement.classList.add('narrow', 'narrow-editor', providerDashName)

    @grammar = new Grammar(@editor, includeHeaderRules: @provider.includeHeaderGrammar)

    @itemIndicator = new ItemIndicator(this)

    @disposables.add @onDidMoveToItemArea =>
      if settings.get('autoShiftReadOnlyOnMoveToItemArea')
        @setReadOnly(true)

    @disposables.add(
      @registerCommands()
      @observeChange()
      @observeStopChanging()
      @observeCursorMove()
      @observeStopChangingActivePaneItem()
    )
    # Depends on ui.grammar and commands bound to @editorElement, so have to come last
    {showSearchOption} = @provider
    @providerPanel = new ProviderPanel(this, {showSearchOption})

    @constructor.register(this)
    @disposables.add new Disposable =>
      @constructor.unregister(this)

  toggleProtect: ->
    @setProtected(not @protected)

  isProtected: ->
    @protected

  setProtected: (@protected) ->
    @itemIndicator.redraw()

  setReadOnly: (readOnly) ->
    @readOnly = readOnly
    if @readOnly
      @editorElement.component?.setInputEnabled(false)
      @editorElement.classList.add('read-only')
      @vmpActivateNormalMode() if @vmpIsInsertMode()
    else
      @editorElement.component.setInputEnabled(true)
      @editorElement.classList.remove('read-only')
      @vmpActivateInsertMode() if @vmpIsNormalMode()

  observeStopChangingActivePaneItem: ->
    atom.workspace.onDidStopChangingActivePaneItem (item) =>
      @syncSubcriptions?.dispose()
      return if item is @editor
      @rowMarker?.destroy()

      # Only sync to text-editor which meet following conditions
      # - Not narrow-editor
      # - Contained in different pane from narrow-editor is contained.
      if (not isTextEditor(item)) or isNarrowEditor(item) or (paneForItem(item) is @getPane())
        return

      if @provider.boundToEditor
        if @provider.editor is item
          @startSyncToEditor(item)
        else
          @provider.bindEditor(item)
          @refresh(force: true).then =>
            @startSyncToEditor(item)
      else
        filePath = item.getPath()
        if @items.some((item) -> item.filePath is filePath)
          @startSyncToEditor(item)

  start: ->
    # When initial getItems() take very long time, it means refresh get delayed.
    # In this case, user see modified icon(mark) on tab.
    # Explicitly setting modified start here prevent this
    @setModifiedState(false)
    if @editorElement.component?
      attachedPromise = Promise.resolve()
    else
      attachedPromise = new Promise (resolve) =>
        disposable = @editorElement.onDidAttach ->
          disposable.dispose()
          resolve()

    if isNarrowEditor(@provider.editor)
      # if narrow is invoked from narrow-editor, open new narrow-editor
      #  on same pane of existing narrow-editor
      @provider.getPane().activateItem(@editor)
    else
      activatePaneItemInAdjacentPane(@editor, split: settings.get('directionToOpen'))

    attachedPromise.then =>
      @grammar.activate()
      if @input
        @setPrompt(@input)
      else
        @withIgnoreChange => @setPrompt(@input)
      @providerPanel.show()
      @moveToPrompt()
      @refresh()


  getPane: ->
    paneForItem(@editor)

  isActive: ->
    isActiveEditor(@editor)

  isPromptRow: (row) ->
    row is 0

  focus: ->
    pane = @getPane()
    pane.activate()
    pane.activateItem(@editor)

  focusPrompt: ->
    if @isActive() and @isPromptRow(@editor.getCursorBufferPosition().row)
      @activateProviderPane()
    else
      @focus() unless @isActive()
      @moveToPrompt()

  toggleFocus: ->
    if @isActive()
      @activateProviderPane()
    else
      @focus()

  activateProviderPane: ->
    if pane = @provider.getPane()
      pane.activate()
      activeItem = pane.getActiveItem()
      if isTextEditor(activeItem)
        activeItem.scrollToCursorPosition()

  destroy: ->
    return if @destroyed
    @destroyed = true
    @highlighter?.destroy()
    @syncSubcriptions?.dispose()
    @disposables.dispose()
    @editor.destroy()
    @activateProviderPane()

    @providerPanel.destroy()
    @provider?.destroy?()
    @itemIndicator?.destroy()
    @rowMarker?.destroy()

  updateRealFile: ->
    return unless @isModified()
    if settings.get('confirmOnUpdateRealFile')
      unless atom.confirm(message: 'Update real file?', buttons: ['Update', 'Cancel']) is 0
        return

    return unless @provider.supportDirectEdit
    return unless @ensureNarrowEditorIsValidState()

    changes = []
    lines = @editor.buffer.getLines()
    for line, row in lines when @isNormalItem(item = @items[row])
      if item._lineHeader?
        line = line[item._lineHeader.length...] # Strip lineHeader
      if line isnt item.text
        changes.push({newText: line, item})

    return unless changes.length

    unless @provider.boundToEditor
      {success, message} = @ensureNoModifiedFileForChanges(changes)
      unless success
        atom.notifications.addWarning(message, dismissable: true)
        return

    {success, message} = @ensureNoConflictForChanges(changes)
    unless success
      atom.notifications.addWarning(message, dismissable: true)
      return

    @provider.updateRealFile(changes)
    @setModifiedState(false)

  # This function is mapped from `narrow:close`
  # To differentiate `narrow:close` for protected narrow-editor.
  # * Two purpose.
  # 1. So that don't close non-protected narrow-editor when narrow:close is
  #   invoked from protected narrow-editor
  # 2. To re-focus to caller editor for not interfering regular preview-then-close-by-ctrl-g flow.
  narrowClose: (event) ->
    if @isProtected()
      event.stopImmediatePropagation()
      @setPrompt('') # clear query
      @activateProviderPane()

  # Just setting cursor position works but it lost goalColumn when that row was skip item's row.
  moveUpOrDown: (event, direction) ->
    cursor = @editor.getLastCursor()
    row = cursor.getBufferRow()

    if (direction is 'next' and row is @editor.getLastBufferRow()) or
        (direction is 'previous' and @isPromptRow(row))
      # This is the command which override `core:move-up`, `core-move-down`
      # So when this command do work, it stop propagation, unless that case
      # this command do nothing and default behavior is still executed.
      ensureCursorIsOneColumnLeftFromEOL = @vmpIsNormalMode()
      event.stopImmediatePropagation()
      row = @findRowForNormalOrPromptItem(row, direction)
      setBufferRow(cursor, row, {ensureCursorIsOneColumnLeftFromEOL})

  # Even in movemnt not happens, it should confirm current item
  # This ensure next-item/previous-item always move to selected item.
  confirmItemForDirection: (direction) ->
    row = @findRowForNormalItem(@getRowForSelectedItem(), direction)
    if row?
      @selectItemForRow(row)
      @confirm(keepOpen: true)

  nextItem: ->
    @confirmItemForDirection('next')

  previousItem: ->
    @confirmItemForDirection('previous')

  previewItemForDirection: (direction) ->
    if not @rowMarker? and direction is 'next'
      # When initial invocation not cause preview(since initial query input was empty).
      # Don't want `tab` skip first seleted item.
      row = @getRowForSelectedItem()
    else
      row = @findRowForNormalItem(@getRowForSelectedItem(), direction)

    if row?
      @selectItemForRow(row)
      @preview()

  previewNextItem: ->
    @previewItemForDirection('next')

  previewPreviousItem: ->
    @previewItemForDirection('previous')

  toggleAutoPreview: ->
    @autoPreview = not @autoPreview
    @preview() if @autoPreview

  getQuery: ->
    @lastNarrowQuery = @editor.lineTextForBufferRow(0)

  excludeFile: ->
    return if @provider.boundToEditor
    return unless selectedItem = @getSelectedItem()
    unless selectedItem.filePath in @excludedFiles
      @excludedFiles.push(selectedItem.filePath)
      nextFileItem = @findDifferentFileItem('next')
      {column} = @editor.getCursorBufferPosition()
      @refresh().then =>
        if nextFileItem
          @selectItem(nextFileItem)
          @moveToSelectedItem(ignoreCursorMove: false)
          {row} = @editor.getCursorBufferPosition()
          @editor.setCursorBufferPosition([row, column])

  clearExcludedFiles: ->
    return if @excludedFiles.length is 0
    @excludedFiles = []
    selectedItem = @getSelectedItem()
    {column} = @editor.getCursorBufferPosition()
    @refresh().then =>
      if selectedItem
        @selectItem(selectedItem)
        @moveToSelectedItem(ignoreCursorMove: false)
        {row} = @editor.getCursorBufferPosition()
        @editor.setCursorBufferPosition([row, column])

  getFilterSpec: ->
    getFilterSpecForQuery(@getQuery())

  refresh: ({force}={}) ->
    @emitWillRefresh()

    if force
      @cachedItems = null

    if @cachedItems?
      promiseForItems = Promise.resolve(@cachedItems)
    else
      promiseForItems = Promise.resolve(@provider.getItems()).then (items) =>
        if @provider.showLineHeader
          @injectLineHeader(items)
        if @provider.supportCacheItems
          @cachedItems = items
        items

    filterSpec = @getFilterSpec()
    if @provider.updateGrammarOnQueryChange
      # No need to highlight excluded items
      @grammar.update(filterSpec.include)

    promiseForItems.then (items) =>
      items = @provider.filterItems(items, filterSpec)
      if not @provider.boundToEditor and @excludedFiles.length
        items = items.filter ({filePath}) => filePath not in @excludedFiles

      @items = [@promptItem, items...]
      @renderItems(items)

      if @isActive()
        @selectItemForRow(@findRowForNormalItem(0, 'next'))
      @setModifiedState(false)
      unless @hasItems()
        @selectedItem = null
        @previouslySelectedItem = null
        @rowMarker?.destroy()
        @rowMarker = null

      @emitDidRefresh()
      @emitDidStopRefreshing()

  renderItems: (items) ->
    texts = items.map (item) => @provider.viewForItem(item)
    @withIgnoreChange =>
      if @editor.getLastBufferRow() is 0
        # Need to recover query prompt
        @setPrompt()
        @moveToPrompt()
        @providerPanel.show() # redraw providerPanel block decoration.
      itemArea = new Range(@itemAreaStart, @editor.getEofBufferPosition())
      range = @editor.setTextInBufferRange(itemArea, texts.join("\n"), undo: 'skip')
      @editorLastRow = range.end.row

  ensureNarrowEditorIsValidState: ->
    unless @editorLastRow is @editor.getLastBufferRow()
      return false

    # Ensure all item have valid line header
    if @provider.showLineHeader
      for line, row in @editor.buffer.getLines() when @isNormalItem(item = @items[row])
        return false unless line.startsWith(item._lineHeader)

    true

  detectConflictForChanges: (changes) ->
    conflictChanges = {}
    changesByFilePath =  _.groupBy(changes, ({item}) -> item.filePath)
    for filePath, changesInFile of changesByFilePath
      changesByRow = _.groupBy(changesInFile, ({item}) -> item.point.row)
      for row, changesInRow of changesByRow
        newTexts = _.pluck(changesInRow, 'newText')
        if _.uniq(newTexts).length > 1
          conflictChanges[filePath] ?= []
          conflictChanges[filePath].push(changesInRow...)
    conflictChanges

  ensureNoConflictForChanges: (changes) ->
    message = []
    conflictChanges = @detectConflictForChanges(changes)
    success = _.isEmpty(conflictChanges)
    unless success
      message.push """
        Cancelled `update-real-file`.
        Detected **conflicting change to same line**.
        """
      for filePath, changesInFile of conflictChanges
        message.push("- #{filePath}")
        for {newText, item} in changesInFile
          message.push("  - #{item.point.translate([1, 1]).toString()}, #{newText}")

    return {success, message: message.join("\n")}

  getModifiedFilePathsInChanges: (changes) ->
    _.uniq(changes.map ({item}) -> item.filePath).filter (filePath) ->
      atom.project.isPathModified(filePath)

  ensureNoModifiedFileForChanges: (changes) ->
    message = ''
    modifiedFilePaths = @getModifiedFilePathsInChanges(changes)
    success = modifiedFilePaths.length is 0
    unless success
      modifiedFilePathsAsString = modifiedFilePaths.map((filePath) -> " - `#{filePath}`").join("\n")
      message = """
        Cancelled `update-real-file`.
        You are trying to update file which have **unsaved modification**.
        But `narrow:#{@provider.getDashName()}` can not detect unsaved change.
        To use `update-real-file`, you need to save these files.

        #{modifiedFilePathsAsString}
        """

    return {success, message}


  observeStopChanging: ->
    @editor.onDidStopChanging =>
      if @autoPreviewOnNextStopChanging
        @preview()
        @autoPreviewOnNextStopChanging = false

  observeChange: ->
    @editor.buffer.onDidChange ({newRange, oldRange}) =>
      return if @ignoreChange

      promptRange = @getPromptRange()
      onPrompt = (range) -> range.intersectsWith(promptRange)
      isQueryModified = (newRange, oldRange) ->
        (not newRange.isEmpty() and onPrompt(newRange)) or (not oldRange.isEmpty() and onPrompt(oldRange))

      if isQueryModified(newRange, oldRange)
        # is Query changed
        if @editor.hasMultipleCursors()
          # Destroy cursors on prompt to protect query from mutation on 'find-and-replace:select-all'( cmd-alt-g ).
          for selection in @editor.getSelections() when onPrompt(selection.getBufferRange())
            selection.destroy()
          @withIgnoreChange =>
            @setPrompt(@lastNarrowQuery) # Recover query
        else
          @refresh().then =>
            if @autoPreviewOnQueryChange and @isActive()
              if @provider.boundToEditor
                @preview()
              else
                # Delay immediate preview unless @provider is boundToEditor
                @autoPreviewOnNextStopChanging = true
      else
        @setModifiedState(true)

  withIgnoreCursorMove: (fn) ->
    @ignoreCursorMove = true
    fn()
    @ignoreCursorMove = false

  withIgnoreChange: (fn) ->
    @ignoreChange = true
    fn()
    @ignoreChange = false

  withPreventAutoPreview: (fn) ->
    @preventAutoPreview = true
    fn()
    @preventAutoPreview = false

  observeCursorMove: ->
    @editor.onDidChangeCursorPosition (event) =>
      return if @ignoreCursorMove

      {oldBufferPosition, newBufferPosition, textChanged, cursor} = event
      return if textChanged or
        (not cursor.selection.isEmpty()) or
        (oldBufferPosition.row is newBufferPosition.row)

      newRow = newBufferPosition.row
      oldRow = oldBufferPosition.row

      if isHeaderRow = @isHeaderRow(newRow)
        direction = if newRow > oldRow then 'next' else 'previous'
        newRow = @findRowForNormalOrPromptItem(newRow, direction)

      if @isPromptRow(newRow)
        @withIgnoreCursorMove =>
          @editor.setCursorBufferPosition([newRow, newBufferPosition.column])
          @emitDidMoveToPrompt()
      else
        @selectItemForRow(newRow)
        @moveToSelectedItem() if isHeaderRow
        @emitDidMoveToItemArea() if @isPromptRow(oldRow)
        @preview() if @autoPreview and not @preventAutoPreview

  findClosestItemForEditor: (editor) ->
    # Detect item
    # - cursor position is equal or greather than that item.
    cursorPosition = editor.getCursorBufferPosition()
    if @provider.boundToEditor
      items = _.reject(@items, (item) -> item.skip)
    else
      # Item must support filePath
      filePath = editor.getPath()
      items = @items.filter((item) -> not item.skip and (item.filePath is filePath))

    for item in items by -1 when @isNormalItem(item)
      # It have only point(no filePath field in each item)
      if item.point.isLessThanOrEqual(cursorPosition)
        break
    return item # return items[0] as fallback

  syncToEditor: (editor) ->
    return if @preventSyncToEditor
    if item = @findClosestItemForEditor(editor)
      @selectItem(item)
      unless @isActive()
        {row} = @editor.getCursorBufferPosition()
        @moveToSelectedItem(scrollToColumnZero: true)
        @emitDidMoveToItemArea() if @isPromptRow(row)

  moveToSelectedItem: ({scrollToColumnZero, ignoreCursorMove}={}) ->
    if (row = @getRowForSelectedItem()) >= 0
      {column} = @editor.getCursorBufferPosition()
      point = scrollPoint = [row, column]
      scrollPoint = [row, 0] if scrollToColumnZero

      moveAndScroll = =>
        # Manually set cursor to center to avoid scrollTop drastically changes
        # when refresh and auto-sync.
        @editor.setCursorBufferPosition(point, autoscroll: false)
        @editor.scrollToBufferPosition(scrollPoint, center: true)

      if ignoreCursorMove ? true
        @withIgnoreCursorMove(moveAndScroll)
      else
        moveAndScroll()

  setRowMarker: (editor, point) ->
    @rowMarker?.destroy()
    @rowMarker = editor.markBufferRange([point, point])
    editor.decorateMarker(@rowMarker, type: 'line', class: 'narrow-result')

  preview: ->
    @preventSyncToEditor = true
    item = @getSelectedItem()
    unless item
      @preventSyncToEditor = false
      @rowMarker?.destroy()
      return

    @provider.openFileForItem(item).then (editor) =>
      editor.scrollToBufferPosition(item.point, center: true)
      @setRowMarker(editor, item.point)
      @preventSyncToEditor = false
      @emitDidPreview({editor, item})

  confirm: ({keepOpen}={}) ->
    return unless @hasNormalItem()
    item = @getSelectedItem()
    @provider.confirmed(item).then =>
      if not keepOpen and not @isProtected() and @provider.getConfig('closeOnConfirm')
        @editor.destroy()

  # Return row
  # Never fail since prompt is row 0 and always exists
  findRowForNormalOrPromptItem: (row, direction) ->
    delta = switch direction
      when 'next' then +1
      when 'previous' then -1

    loop
      row = getValidIndexForList(@items, row + delta)
      if @isNormalItemRow(row) or @isPromptRow(row)
        return row

  # Return row
  findRowForNormalItem: (row, direction) ->
    return null unless @hasNormalItem()
    delta = switch direction
      when 'next' then +1
      when 'previous' then -1

    loop
      if @isNormalItemRow(row = getValidIndexForList(@items, row + delta))
        return row

  findDifferentFileItem: (direction) ->
    return if @provider.boundToEditor
    return null unless @hasNormalItem()
    return null unless selectedItem = @getSelectedItem()

    delta = switch direction
      when 'next' then +1
      when 'previous' then -1

    startRow = row = @getRowForSelectedItem()
    while (row = getValidIndexForList(@items, row + delta)) isnt startRow
      if @isNormalItemRow(row) and @items[row].filePath isnt selectedItem.filePath
        return @items[row]

  isCursorOutOfSyncWithSelectedItem: ->
    @editor.getCursorBufferPosition().row isnt @getRowForSelectedItem()

  moveToNextFileItem: ->
    @moveToDifferentFileItem('next')

  moveToPreviousFileItem: ->
    @moveToDifferentFileItem('previous')

  moveToDifferentFileItem: (direction) ->
    if @isCursorOutOfSyncWithSelectedItem()
      @moveToSelectedItem(ignoreCursorMove: false)
      return

    # Fallback to selected item incase there is only single filePath in all items
    # But whant to move to that item from query-prompt.
    if item = @findDifferentFileItem(direction) ? @getSelectedItem()
      @selectItem(item)
      @moveToSelectedItem(ignoreCursorMove: false)

  moveToPromptOrSelectedItem: ->
    row = @getRowForSelectedItem()
    if (row is @editor.getCursorBufferPosition().row) or not (row >= 0)
      @moveToPrompt()
    else
      # move to current item
      @editor.setCursorBufferPosition([row, 0])

  isNormalItem: (item) ->
    item? and not item.skip

  getRowForSelectedItem: ->
    @getRowForItem(@getSelectedItem())

  moveToPrompt: ->
    @withIgnoreCursorMove =>
      @editor.setCursorBufferPosition(@getPromptRange().end)
      @setReadOnly(false)
      @emitDidMoveToPrompt()

  isNormalItemRow: (row) ->
    @isNormalItem(@items[row])

  isHeaderRow: (row) ->
    not @isPromptRow(row) and not @isNormalItemRow(row)

  hasNormalItem: ->
    normalItems = @items.filter (item) => @isNormalItem(item)
    normalItems.length > 0

  getRowForItem: (item) ->
    @items.indexOf(item)

  selectItem: (item) ->
    if (row = @getRowForItem(item)) >= 0
      @selectItemForRow(row)

  hasItems: ->
    @items.length > 1 # ignore prompt placeholder item

  selectItemForRow: (row) ->
    item = @items[row]
    if @isNormalItem(item)
      @itemIndicator.setToRow(row)
      @previouslySelectedItem = @selectedItem
      @selectedItem = item
      event = {
        oldItem: @previouslySelectedItem
        newItem: @selectedItem
      }
      @emitDidChangeSelectedItem(event)

  getSelectedItem: ->
    @selectedItem

  getPreviouslySelectedItem: ->
    @previouslySelectedItem

  getPromptRange: ->
    @editor.bufferRangeForBufferRow(0)

  # Return range
  setPrompt: (text='') ->
    if @editor.getLastBufferRow() is 0
      text += "\n"
    range = @editor.setTextInBufferRange(@getPromptRange(0), text)
    range

  isSyncingEditor: (editor) ->
    @syncingEditor? and @syncingEditor is editor

  startSyncToEditor: (editor) ->
    @syncingEditor = editor
    @syncToEditor(editor)
    @syncSubcriptions = new CompositeDisposable
    @syncSubcriptions.add editor.onDidChangeCursorPosition (event) =>
      if isActiveEditor(editor) and (not event.textChanged)
        if @provider.ignoreSideMovementOnSyncToEditor
          return if event.oldBufferPosition.row is event.newBufferPosition.row

        @syncToEditor(editor)

    @syncSubcriptions.add @onDidRefresh =>
      @syncToEditor(editor)

    if @provider.boundToEditor
      @syncSubcriptions.add editor.onDidStopChanging =>
        # Surppress refreshing while editor is active to avoid auto-refreshing while direct-edit.
        @refresh(force: true) unless @isActive()
    else
      @syncSubcriptions.add editor.onDidSave =>
        @refresh(force: true) unless @isActive()

  # Return intems which are injected maxLineTextWidth(used to align lineHeader)
  injectLineHeader: (items) ->
    normalItems = _.reject(items, (item) -> item.skip)
    points = _.pluck(normalItems, 'point')
    maxLine = Math.max(_.pluck(points, 'row')...) + 1
    maxColumn = Math.max(_.pluck(points, 'column')...) + 1
    maxLineWidth = String(maxLine).length
    maxColumnWidth = Math.max(String(maxColumn).length, 2)
    for item in normalItems
      item._lineHeader = @getLineHeaderForItem(item.point, maxLineWidth, maxColumnWidth)
    items

  getNormalItems: ->
    @items.filter (item) -> (not item.skip)

  getNormalItemsForFilePath: (filePath) ->
    @items.filter (item) ->
      (not item.skip) and (item.filePath is filePath)

  getLineHeaderForItem: (point, maxLineWidth, maxColumnWidth) ->
    lineText = String(point.row + 1)
    padding = " ".repeat(maxLineWidth - lineText.length)
    lineHeader = "#{@provider.indentTextForLineHeader}#{padding}#{lineText}"
    if @provider.showColumnOnLineHeader
      columnText = String(point.column + 1)
      padding = " ".repeat(maxColumnWidth - columnText.length)
      lineHeader = "#{lineHeader}:#{padding}#{columnText}"
    lineHeader + ": "

  # vim-mode-plus integration
  # -------------------------
  vmpActivateNormalMode: ->
    atom.commands.dispatch(@editorElement, 'vim-mode-plus:activate-normal-mode')

  vmpActivateInsertMode: ->
    atom.commands.dispatch(@editorElement, 'vim-mode-plus:activate-insert-mode')

  vmpIsInsertMode: ->
    @vmpIsEnabled() and @editorElement.classList.contains('insert-mode')

  vmpIsNormalMode: ->
    @vmpIsEnabled() and @editorElement.classList.contains('normal-mode')

  vmpIsEnabled: ->
    @editorElement.classList.contains('vim-mode-plus')
