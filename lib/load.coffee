# lib\load.coffee

fs         = require 'fs'
zlib       = require 'zlib'
pathUtil   = require 'path'
mkdirp     = require 'mkdirp'
binSrch    = require 'binarysearch'
save       = require './save'
dbg        = require('./utils').debug 'load'

DIFF_EQUAL  = 0
DIFF_INSERT = 1
DIFF_BASE   = 2
DIFF_DELETE = 3
DIFF_TYPE_MASK  = 0x30
DIFF_TYPE_SHIFT = 4
DIFF_COMPRESSED_MASK  = 0x40
DIFF_COUNT_CODE_MASK  = 0x0f

curPath = dataPath = ''
index = []

readUIntN = (n, buf, ofs) ->
  num = 0
  for i in [0...n]
    num *= 0x100
    num |= buf.readUInt8 ofs++, yes
  num

getDeltaHdr = (fdIn, fileOfs) ->
  flagsLen = (if fileOfs is 0 then 0 else 4)  
  buf = new Buffer 16
  fd = (if fdIn then fdIn else fs.openSync dataPath, 'r')
  fs.readSync fd, buf, 0, 16, fileOfs - flagsLen
  if not fdIn then fs.closeSync fd
  pos = 0
  if flagsLen
    flags = buf.readUInt32BE pos, yes
    if flags isnt 0xffffffff 
      throw new Exception 'corrupt live-archive data: ' + dataPath + ', ' + fileOfs
  pos += flagsLen
  hdrByte = buf.readUInt8 pos, yes
  pos += 1
  deltaLenLen = hdrByte & 0x07
  deltaLen = readUIntN deltaLenLen, buf, pos
  pos += deltaLenLen
  time = buf.readUInt32BE pos, yes
  pos += 4
  hasBase = ((buf.readUInt8(pos, yes) & DIFF_TYPE_MASK) >>> DIFF_TYPE_SHIFT) is DIFF_BASE
  {time, hdrLen: pos - flagsLen, deltaLen, hasBase}

readDiff = (buf, ofs) ->
  hdrByte    = buf.readUInt8 ofs, yes
  compressed = ((hdrByte & DIFF_COMPRESSED_MASK) is DIFF_COMPRESSED_MASK)
  diffType   = ((hdrByte & DIFF_TYPE_MASK) >>> DIFF_TYPE_SHIFT)
  countCode  =   hdrByte & DIFF_COUNT_CODE_MASK
  if countCode <= 9
    numBytesInDiffDataLen = 0
    diffDataLen = countCode
  else
    numBytesInDiffDataLen = countCode - 9
    diffDataLen = 0
    for lenByteOfs in [1..numBytesInDiffDataLen]
      diffDataLen *= 0x100
      diffDataLen |= buf.readUInt8 ofs + lenByteOfs, yes
  diffLen = 1 + numBytesInDiffDataLen
  diffStr = null
  if diffType isnt DIFF_EQUAL
    diffLen += diffDataLen
    dataOfs = ofs + 1 + numBytesInDiffDataLen
    diffDataBuf = buf.slice dataOfs, dataOfs + diffDataLen
    if compressed then diffDataBuf = zlib.inflateSync diffDataBuf
    diffStr = diffDataBuf.toString()
  {diffType, diffStr, diffLen, diffDataLen}

processDeltas = (text, idx, idxInc, endIdx, baseIdx, baseDiffsBuf) ->
  fd = fs.openSync dataPath, 'r'
  diffsBufs = []
  loop
    if idx is baseIdx
        diffsBufs.push baseDiffsBuf
    else
      {fileBegPos} = index[idx]
      {hdrLen, deltaLen} = getDeltaHdr fd, fileBegPos
      diffsLen = deltaLen - hdrLen - 4
      diffsBuf = new Buffer diffsLen
      fs.readSync fd, diffsBuf, 0, diffsLen, fileBegPos + hdrLen
      diffsBufs.push diffsBuf
    if (idx += idxInc) is endIdx then break
  fs.closeSync fd
  for diffsBuf in diffsBufs
    diffPos = textPos = 0
    nextText = ''
    while diffPos < diffsBuf.length
      {diffType, diffStr, diffLen, diffDataLen} = readDiff diffsBuf, diffPos
      if diffType isnt DIFF_BASE
        if idxInc < 0
          if      diffType is DIFF_DELETE then diffType = DIFF_INSERT
          else if diffType is DIFF_INSERT then diffType = DIFF_DELETE
        switch diffType
          when DIFF_EQUAL
            nextText += text[textPos...(textPos + diffDataLen)]
            textPos  += diffDataLen
          when DIFF_DELETE then textPos  += diffStr.length
          when DIFF_INSERT then nextText += diffStr
      else
      diffPos += diffLen
    text = nextText
  {text, deltaLen}

getTextAndPos = (idx, time) ->
  if index.length is 0 then return {text: '', index: -1}
  if time?
    idx = binSrch.closest index, time, (entry, tgt) -> entry.time - tgt
    if time < index[idx].time then idx--
  if idx < 0 then return {text: '', index: -1}
  tgtIdx = endIdx = idx
  dist = 0
  loop
    dist = -dist
    if (baseEntry = index[endIdx + dist]) and baseEntry.hasBase then break
    if dist <= 0 then dist--
  baseIdx = endIdx + dist
  {hdrLen, deltaLen} = getDeltaHdr null, baseEntry.fileBegPos
  baseDiffsLen = deltaLen - hdrLen - 4
  baseDiffsBuf = new Buffer baseDiffsLen
  fd = fs.openSync dataPath, 'r'
  fs.readSync fd, baseDiffsBuf, 0, baseDiffsLen, baseEntry.fileBegPos + hdrLen
  fs.closeSync fd
  baseText = readDiff(baseDiffsBuf, 0).diffStr
  if tgtIdx is baseIdx
    return {text: baseText, index: baseIdx}
  idxInc = (if dist < 0 then 1 else -1)
  idx = baseIdx
  if idxInc > 0 then idx++; endIdx++
  {text} = processDeltas baseText, idx, idxInc, endIdx, baseIdx, baseDiffsBuf
  {text, index: tgtIdx}

getHdrLen = (hdrFilePos) ->
  buf = new Buffer 7
  fd = fs.openSync dataPath, 'r'
  fs.readSync fd, buf, 0, 7, hdrFilePos
  fs.closeSync fd
  hdrByte = buf.readUInt8 0, yes
  1 + (hdrByte & 0x07) + 4
  
diffsForOneIdx = (idx, includeDataStr) ->
  if idx >= index.length then return []
  {fileBegPos, fileEndPos} = index[idx]
  hdrLen = getHdrLen fileBegPos
  diffOfs = fileBegPos + hdrLen
  diffsLen = (fileEndPos - fileBegPos) - hdrLen - 4
  buf = new Buffer diffsLen
  fd = fs.openSync dataPath, 'r'
  fs.readSync fd, buf, 0, diffsLen, diffOfs
  fs.closeSync fd
  diffs = []
  pos = 0
  while pos < diffsLen
    hdrByte    = buf.readUInt8 pos, yes
    compressed = ((hdrByte & DIFF_COMPRESSED_MASK) is DIFF_COMPRESSED_MASK)
    diffType   = ((hdrByte & DIFF_TYPE_MASK) >>> DIFF_TYPE_SHIFT)
    countCode  =   hdrByte & DIFF_COUNT_CODE_MASK
    if countCode <= 9
      numBytesInDiffDataLen = 0
      diffDataLen = countCode
    else
      numBytesInDiffDataLen = countCode - 9
      diffDataLen = 0
      for lenByteOfs in [1..numBytesInDiffDataLen]
        diffDataLen *= 0x100
        diffDataLen |= buf.readUInt8 pos + lenByteOfs, yes
    if diffType isnt DIFF_BASE
      diff = [diffType, diffDataLen]
      if includeDataStr and diffType isnt DIFF_EQUAL
        dataOfs = pos + 1 + numBytesInDiffDataLen
        diffDataBuf = buf.slice dataOfs, dataOfs + diffDataLen
        if compressed then diffDataBuf = zlib.inflateSync diffDataBuf
        diff.push diffDataBuf.toString()
      diffs.push diff
    pos += 1 + numBytesInDiffDataLen +
          (if diffType is DIFF_EQUAL then 0 else diffDataLen)
  diffs

scanForDiffs = (idx, twoIdx) ->
  retrn = diffsForIdx: diffsForOneIdx idx
  if twoIdx then retrn.diffsForNextIdx = diffsForOneIdx idx + 1
  retrn
      
getIndexes = (pos) ->
  idx = index.length
  try 
    fileSize = fs.statSync(dataPath).size
  catch e
    fileSize = 0
  if pos is fileSize then return
  fd = fs.openSync dataPath, 'r'
  while pos < fileSize
    {time, deltaLen, hasBase} = getDeltaHdr fd, pos
    index.push {
      fileBegPos: pos
      fileEndPos: pos + deltaLen
      idx: idx++
      hasBase, time
    }
    pos += deltaLen
  if pos > 0
    flagsBuf = new Buffer 4
    fs.readSync fd, flagsBuf, 0, 4, pos-4
    flags = flagsBuf.readUInt32BE 0, yes
    if flags isnt 0xffffffff
      fs.closeSync fd 
      throw new Exception 'corrupt live-archive data at end: ' + dataPath + ', ' + fileSize
  fs.closeSync fd

setPath = (path, chkBase) ->
  if path isnt curPath or not fs.existsSync path
    curPath = path
    index = []
    if path
      mkdirp.sync pathUtil.dirname path
      dataPath = path
      fs.closeSync fs.openSync dataPath, 'a'
      
  if path 
    getIndexes(if index.length > 0 then index[index.length-1].fileEndPos else 0)
   
  if chkBase and index.length > 0
    versionsSinceBase = 0
    sizeSinceBase = null
    now = Date.now() 
    totalFileSize = index[index.length-1].fileEndPos
    for idx in [index.length-1..0] by -1
      entry = index[idx]
      if entry.hasBase then break
      versionsSinceBase++
      sizeSinceBase = totalFileSize - entry.fileEndPos
    if sizeSinceBase and (versionsSinceBase > 100 or sizeSinceBase > 10000)
      save.setNeedsBase path, {versionsSinceBase, sizeSinceBase}

load = exports

load.getPath = (projPath, filePath) ->
  liveArchiveDir = projPath + '/.live-archive'
  if not fs.existsSync liveArchiveDir then return {}
  projDirs  = projPath.split /\/|\\/g
  fileParts = filePath.split /\/|\\/g
  pathDir = liveArchiveDir +
    (if fileParts.length - projDirs.length < 2 then '' else  '/') +
    fileParts[projDirs.length..-2].join('/')
  mkdirp.sync pathDir
  path = pathDir + '/' + fileParts[fileParts.length-1] + '.la'
  try
    dataFileSize = fs.statSync(path).size
  catch e
    dataFileSize = 0
  {path, dataFileSize}

load.getTime = (idx) -> index[idx]?.time
  
load.lastIndex = (path) ->
  setPath path
  (if index.length > 0 then index.length-1 else -1)

load.getDiffs = (projPath, filePath, idx, twoIdx) ->
  if not (path = load.getPath(projPath, filePath).path) 
    return diffsForIdx: [], inserts: [], deletes: []
  setPath path
  {diffsForIdx, diffsForNextIdx} = scanForDiffs idx, twoIdx
  if not twoIdx then return {diffsForIdx}
  inserts = []
  pos = 0
  for diff in diffsForIdx
    [type, len] = diff
    if type is   DIFF_INSERT then inserts.push [pos, pos+len]
    if type isnt DIFF_DELETE then pos += len
  deletes = []
  pos = 0
  for diff in diffsForNextIdx
    [type, len] = diff
    if type is   DIFF_DELETE then deletes.push [pos, pos+len]
    if type isnt DIFF_INSERT then pos += len
  {inserts, deletes}

load.searchDiffs = (projPath, filePath, idx, inc, searchStr) ->
  if not (path = load.getPath(projPath, filePath).path)
    return positions
  setPath path
  loop
    idx += inc
    if not (0 <= idx < index.length) then return
    diffs = diffsForOneIdx idx, yes
    textPos = 0
    for diff in diffs
      [diffType, diffDataLen, strData] = diff
      if strData and strData.toLowerCase().indexOf(searchStr) > -1
        return {idx, textPos}
      textPos += diffDataLen

load.text = (projPath, filePath, idx, time) ->
  if not (path = load.getPath(projPath, filePath).path) then return {text: ''}
  setPath path, yes
  idx ?= index.length - 1
  if idx < 0 then return {text: ''}
  strt = Date.now()
  text = getTextAndPos idx, time
  # dbg 'load text delay ms', Date.now() - strt
  text

