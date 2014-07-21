
fs       = require 'fs'
pathUtil = require 'path'
mkdirp   = require 'mkdirp'
binSrch  = require 'binarysearch'

DIFF_DELETE = -1
DIFF_EQUAL  =  0
DIFF_INSERT =  1
DIFF_BASE   =  2

maxTextCacheAge  = 60 * 1000
maxTextCacheSize = 1e6

curPath = indexPath = dataPath = ''
index         = []
textCache     = {}
textCacheSize = 0

readUInt48 = (buf, ofs) ->
  ms16 = buf.readUInt16BE ofs,   yes
  ls32 = buf.readUInt32BE ofs+2, yes
  ms16 * 0x100000000 + ls32

indexEntryLen = 20
readIndexEntry = (buf, pos) ->
  # deltaVersion = buf.readUInt16 pos, yes
  saveTime   = readUInt48 buf, pos + 2
  fileBegPos = readUInt48 buf, pos + 8
  fileEndPos = readUInt48 buf, pos + 14
  {saveTime, fileBegPos, fileEndPos}

diffHdrLen = 8
readDiffHdr = (buf, pos) ->
  # diffVersion = buf.readUInt8 pos, yes
  diffType = buf.readInt8    pos + 1, yes
  diffLen  = readUInt48 buf, pos + 2
  {diffType, diffLen}

deltaEndFlagLen = 6

pruneTextCache = ->
  if textCacheSize < maxTextCacheSize then return

  now = Date.now()
  dateLens = []
  for date, text of textCache
    if +date < now - maxTextCacheAge
      textCacheSize -= text.length
      delete textCache[date]
      continue
    dateLens.push [date, text.length]
  if textCacheSize < maxTextCacheSize then return

  dates.sort()
  for dateLen in dateLens
      [date, len] = dateLen
      textCacheSize -= len
      delete textCache[date]
      if textCacheSize <= maxTextCacheSize then return
  null

timeToStr = (time) ->
  str = '' + time
  while str.length < 15 then str = '0' + str
  str

getFileLen = (path) ->
  try
    stats = fs.statSync path
  catch e
    return 0
  stats.size

getText = (timeTgt) ->
  if (text = textCache[timeToStr timeTgt]) then return text
  if index.length is 0 or timeTgt < index[0].saveTime then return ''

  idx = binSrch.closest index, timeTgt, (val, find) -> val.saveTime - find
  saveTime = index[idx].saveTime
  if timeTgt < saveTime then (if idx then idx-- else return '')
  if (text = textCache[timeToStr saveTime]) then return text

  fd = fs.openSync pathUtil.join(curPath, 'data'), 'r'
  deltas = []
  for i in [idx..0] by -1
    {saveTime, fileBegPos, fileEndPos} = index[i]
    if (baseText = textCache[timeToStr saveTime])
      break
    deltaLen = fileEndPos - fileBegPos
    deltaBuf = new Buffer deltaLen
    fs.readSync fd, deltaBuf, 0, deltaLen, fileBegPos
    {diffType, diffLen} = readDiffHdr deltaBuf, indexEntryLen
    if diffType is DIFF_BASE
      diffPos  = indexEntryLen + diffHdrLen
      baseText = deltaBuf.toString 'utf8', diffPos, diffPos + diffLen
      break
    deltas.unshift {saveTime, deltaBuf}
  fs.closeSync fd

  cachecount = 0
  curText = baseText

  for delta in deltas
    {saveTime, deltaBuf} = delta
    deltaPos = indexEntryLen
    curTextPos = 0
    nextText = ''
    while deltaPos < deltaBuf.length - deltaEndFlagLen
      {diffType, diffLen} = readDiffHdr deltaBuf, deltaPos
      deltaPos += diffHdrLen
      switch diffType
        when DIFF_EQUAL
          nextText   += curText[curTextPos...(curTextPos+diffLen)]
          curTextPos += diffLen
        when DIFF_DELETE
          curTextPos += diffLen
        when DIFF_INSERT
          diffPos = deltaPos + diffHdrLen
          nextText += deltaBuf.toString 'utf8', deltaPos, deltaPos + diffLen
          deltaPos += diffLen
    curText = nextText

    if ++cachecount % 10 is 0
      textCache[timeToStr saveTime] = curText
      textCacheSize += curText.length
      pruneTextCache()

  curText

setPath = (path) ->
  if path isnt curPath
    curPath = path
    index = []
    textCache = {}
    textCacheSize = 0

    if path
      mkdirp.sync path
      indexPath = pathUtil.join path, 'index'
      fs.closeSync fs.openSync indexPath, 'a'
      dataPath  = pathUtil.join path, 'data'
      fs.closeSync fs.openSync dataPath, 'a'
      indexBuf = fs.readFileSync indexPath
      for pos in [0...indexBuf.length] by indexEntryLen
        index.push readIndexEntry indexBuf, pos

  if path
    indexSize = index.length * indexEntryLen
    fileSize  = getFileLen indexPath
    if indexSize < fileSize
      indexBuf = fs.readFileSync indexPath
      for pos in [indexSize...fileSize] by indexEntryLen
        index.push readIndexEntry indexBuf, pos

load = exports

load.text = (path, saveTime = Infinity) ->
  setPath path
  getText saveTime
