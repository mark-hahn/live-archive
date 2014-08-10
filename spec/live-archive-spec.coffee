
fs          = require 'fs'
pathUtil    = require 'path'

LiveArchive = require '../lib/live-archive'
load        = require '../lib/load'
save        = require '../lib/save'
mkdirp      = require 'mkdirp'

# Use the command `window:run-package-specs` (cmd-alt-ctrl-p) to run specs.
#
# To run a specific `it` or `describe` block add an `f` to the front (e.g. `fit`
# or `fdescribe`). Remove the `f` to unfocus the block.

describe "LiveArchive", ->
  describe "when testing load/save", ->
    beforeEach ->
      projectRoot = __dirname
      mkdirp.sync projectRoot + '/.live-archive'
      @paths = [ projectRoot, projectRoot + '/fake.file' ]
      @path  = load.getPath(@paths...).path
      try
        fs.unlinkSync @path
      catch e

    it "saves and loads small strings", ->
      idx = 0
      v1  = 'text'
      v2  = 'T E\n xt'
      v3  = 'TexT'
      
      changed = save.text @paths..., v1, 1, 2
      idx1 = idx++
      expect(changed).toBe yes
      changed = save.text @paths..., v2, 3, 4
      idx2 = idx++
      expect(changed).toBe yes

      expect(load.text @paths...).toEqual {text:v2, index: 1, lineNum: 3, charOfs: 4, auto: no}

      changed = save.text @paths..., v3, 5, 6, yes
      idx3 = idx++
      expect(changed).toBe yes

      expect(load.text @paths...,   idx1).toEqual {text:v1, index:  0, lineNum: 1, charOfs: 2, auto: no}
      expect(load.text @paths...,   idx2).toEqual {text:v2, index:  1, lineNum: 3, charOfs: 4, auto: no}
      expect(load.text @paths...,   idx3).toEqual {text:v3, index:  2, lineNum: 5, charOfs: 6, auto: no}
      expect(load.text @paths...        ).toEqual {text:v3, index:  2, lineNum: 5, charOfs: 6, auto: no}

      expect(load.getDiffs @paths..., idx2, yes).toEqual 
        inserts : [ [ 0, 5 ] ]
        deletes : [ [ 1, 5 ], [ 6, 7 ] ]
        
