path = require 'path'
_ = require 'underscore-plus'
{Point, BufferedProcess} = require 'atom'
SearchBase = require './search-base'

runCommand = (options) ->
  new BufferedProcess(options).onWillThrowError ({error, handle}) ->
    if error.code is 'ENOENT' and error.syscall.indexOf('spawn') is 0
      console.log "ERROR"
    handle()

parseLine = (line) ->
  m = line.match(/^(.*?):(\d+):(\d+):(.*)$/)
  if m?
    {
      relativePath: m[1]
      point: new Point(parseInt(m[2]) - 1, parseInt(m[3]) - 1)
      text: m[4]
    }
  else
    null

getOutputterForProject = (project, items) ->
  projectName = path.basename(project)
  projectHeaderAdded = false
  currentFilePath = null
  (data) ->
    unless projectHeaderAdded
      header = "# #{projectName}"
      items.push({header, projectName, projectHeader: true, skip: true})
      projectHeaderAdded = true

    for line in data.split("\n") when parsed = parseLine(line)
      {relativePath, point, text} = parsed
      filePath = path.join(project, relativePath)

      if currentFilePath isnt filePath
        currentFilePath = filePath
        header = "## #{relativePath}"
        items.push({header, projectName, filePath, skip: true})

      items.push({point, text, filePath, projectName})

# Not used but keep it since I'm planning to introduce per file refresh on modification
getOutputterForFile = (items) ->
  (data) ->
    for line in data.split("\n") when parsed = parseLine(line)
      {relativePath, point, text} = parsed
      items.push({point, text, filePath: relativePath})

module.exports =
class Search extends SearchBase
  supportCacheItems: true

  checkReady: ->
    if @options.currentProject
      for dir in atom.project.getDirectories() when dir.contains(@editor.getPath())
        @options.projects = [dir.getPath()]
        break

      unless @options.projects?
        message = "#{@editor.getPath()} not belonging to any project"
        atom.notifications.addInfo(message, dismissable: true)
        return Promise.resolve(false)

    super

  getItems: ->
    searchPromises = []
    for project in @options.projects ? atom.project.getPaths()
      searchPromises.push(@search(@regExpForSearchTerm, {project}))

    searchTermLength = @options.search.length
    Promise.all(searchPromises).then (values) ->
      _.flatten(values).map (item) ->
        if point = item.point
          item.range = [point, point.translate([0, searchTermLength])]
        item

  search: (regexp, {project, filePath}) ->
    items = []
    args = @getConfig('agCommandArgs').split(/\s+/)

    if regexp.ignoreCase
      args.push('--ignore-case')
    else
      args.push('--case-sensitive')

    options =
      stdio: ['ignore', 'pipe', 'pipe']
      env: process.env

    args.push(regexp.source)

    if filePath?
      stdout = stderr = getOutputterForFile(items)
      args.push(filePath)
    else
      stdout = stderr = getOutputterForProject(project, items)
      options.cwd = project

    new Promise (resolve) ->
      runCommand(
        command: 'ag'
        args: args
        stdout: stdout
        stderr: stderr
        exit: -> resolve(items)
        options: options
      )
