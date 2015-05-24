
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
      v0  = 'text'
      v1  = 'T E\n xt'
      v2  = 'TexT'
      
      changed = save.text @paths..., v0, 1, 2
      expect(changed).toBe yes
      
      changed = save.text @paths..., v1, 3, 4
      expect(changed).toBe yes

      expect(load.text @paths...).toEqual {text:v1, index: 1, lineNum: 3, charOfs: 4, auto: no}

      changed = save.text @paths..., v2, 5, 6, yes
      expect(changed).toBe yes

      expect(load.text @paths..., 0).toEqual {text:v0, index:  0, lineNum: 1, charOfs: 2, auto: no}
      expect(load.text @paths..., 1).toEqual {text:v1, index:  1, lineNum: 3, charOfs: 4, auto: no}
      expect(load.text @paths..., 2).toEqual {text:v2, index:  2, lineNum: 5, charOfs: 6, auto: no}
      expect(load.text @paths...   ).toEqual {text:v2, index:  2, lineNum: 5, charOfs: 6, auto: no}

      expect(load.getDiffs @paths..., 1, yes).toEqual 
        inserts : [ [ 0, 5 ] ]
        deletes : [ [ 1, 5 ], [ 6, 7 ] ]
          
      expect(load.getDiffs @paths..., 2, yes).toEqual 
        inserts : [ [ 1, 2 ], [ 3, 4 ] ]
        deletes : [  ]  
        
      expect(load.trackPos @paths..., 0, 0, [0,1,2,3]      ).toEqual [0,1,2,3]
      expect(load.trackPos @paths..., 0, 1, [0,1,2,3]      ).toEqual [0,0,5,6]
      expect(load.trackPos @paths..., 0, 2, [0,1,2,3]      ).toEqual [0,0,2,2]
      expect(load.trackPos @paths..., 1, 0, [0,1,2,3,4,5,6]).toEqual [1,1,1,1,1,2,3]
      expect(load.trackPos @paths..., 1, 1, [0,1,2,3,4,5,6]).toEqual [0,1,2,3,4,5,6]
      expect(load.trackPos @paths..., 1, 2, [0,1,2,3,4,5,6]).toEqual [0,0,0,0,0,2,2]
      expect(load.trackPos @paths..., 2, 0, [0,1,2,3]      ).toEqual [1,1,2,3]
      expect(load.trackPos @paths..., 2, 1, [0,1,2,3]      ).toEqual [0,4,5,6]
      expect(load.trackPos @paths..., 2, 2, [0,1,2,3]      ).toEqual [0,1,2,3]
      
      expect(load.trackPos @paths..., 0, 1, [0,1,2]  ).toEqual [0,0,5]
      expect(load.trackPos @paths..., 0, 2, [1,2,3]  ).toEqual [0,2,2]
      expect(load.trackPos @paths..., 1, 0, [0,2,4,5]).toEqual [1,1,1,2]
      expect(load.trackPos @paths..., 1, 2, [0]      ).toEqual [0]
      expect(load.trackPos @paths..., 2, 0, [1]      ).toEqual [1]
      expect(load.trackPos @paths..., 2, 1, [3]      ).toEqual [6]

      
      