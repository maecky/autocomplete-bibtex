{Range}  = require "atom"
{Provider, Suggestion} = require "autocomplete-plus-minimal"
fuzzaldrin = require "fuzzaldrin"
_ = require "underscore-plus"
fs = require "fs"
require "sugar"
bibtexParse = require "zotero-bibtex-parse"
XRegExp = require('xregexp').XRegExp

module.exports =
class BibtexProvider extends Provider
  wordRegex: XRegExp('@[\\p{Letter}\\p{Number}\._-]*', 'g')
  exclusive: true
  bibtex: []
  possibleWords: []
  resultTemplate: ''
  initialize: ->
    resultTemplate = atom.config.get "autocomplete-bibtex.resultTemplate"

    if @possibleWords.length is 0
      if @bibtex.length is 0
        @readBibtexFiles(atom.config.get "autocomplete-bibtex.bibtex")

      @buildWordList()

    atom.config.observe "autocomplete-bibtex.bibtex", (bibtex) =>
      @readBibtexFiles(bibtex)
      @buildWordList()
    atom.config.observe "autocomplete-bibtex.resultTemplate", (resultTemplate) =>
      @resultTemplate = resultTemplate

  readBibtexFiles: (files) =>
    try
      bibtex = []

      for file in files
        parser = new bibtexParse(fs.readFileSync(file, 'utf-8'))

        bibtex = bibtex.concat parser.parse()

      @bibtex = bibtex
    catch error
      console.error error

  buildWordList: =>
    possibleWords = []

    for citation in @bibtex
      citation.entryTags.prettyTitle =
        @prettifyTitle citation.entryTags.title

      citation.entryTags.authors =
        @cleanAuthors citation.entryTags.author?.split ' and '
      citation.entryTags.prettyAuthors =
        @prettifyAuthors citation.entryTags.authors

      for author in citation.entryTags.authors
        possibleWords.push {
          author: @prettifyName(author, yes),
          key: citation.citationKey,
          label: "#{citation.entryTags.prettyTitle} \
            by #{citation.entryTags.prettyAuthors}"
        }

    @possibleWords = possibleWords

  buildSuggestions: ->
    selection = @editor.getSelection()
    prefix = @prefixOfSelection selection
    return unless prefix.length

    suggestions = @findSuggestionsForPrefix prefix
    return unless suggestions.length
    return suggestions

  findSuggestionsForPrefix: (prefix) ->
    prefix = prefix.replace /^@/, ''

    words = fuzzaldrin.filter @possibleWords, prefix, { key: 'author' }

    suggestions = for word in words
      new Suggestion this,
        word: word.author,
        prefix: prefix,
        label: word.label
        data:
          body: @resultTemplate.replace('[key]', word.key)

    return suggestions

  confirm: (suggestion) ->
    selection = @editor.getSelection()
    startPosition = selection.getBufferRange().start
    buffer = @editor.getBuffer()

    # Replace the prefix with the body
    cursorPosition = @editor.getCursorBufferPosition()
    buffer.delete Range.fromPointWithDelta(cursorPosition, 0, -(suggestion.prefix.length + 1))
    @editor.insertText suggestion.data.body

    # Move the cursor behind the body
    suffixLength = suggestion.data.body.length - (suggestion.prefix.length + 1)
    @editor.setSelectedBufferRange \
      [startPosition, [startPosition.row, startPosition.column + suffixLength]]

    return false # Don't fall back to the default behavior

  prettifyTitle: (title) ->
    if (colon = title.indexOf(':')) isnt -1 and title.words().length > 5
      title = title.substring(0, colon)

    title.titleize().truncateOnWord 30, 'middle'

  cleanAuthors: (authors) ->
    if not authors? then return [{ familyName: 'Unknown' }]

    for author in authors
      [familyName, personalName] =
        if author.indexOf(', ') isnt -1 then author.split(', ') else [author]

      { personalName: personalName, familyName: familyName }

  prettifyAuthors: (authors) ->
    name = @prettifyName authors[0]

    if authors.length > 1 then "#{name} et al." else "#{name}"

  prettifyName: (person, inverted = no, separator = ' ') ->
    if inverted
      @prettifyName {
        personalName: person.familyName,
        familyName: person.personalName
      }, no, ', '
    else
      (if person.personalName? then person.personalName else '') + \
      (if person.personalName? and person.familyName? then separator else '') + \
      (if person.familyName? then person.familyName else '')
