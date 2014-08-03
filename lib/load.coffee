# lib\load.coffee

fs         = require 'fs'
pathUtil   = require 'path'
mkdirp     = require 'mkdirp'
binSrch    = require 'binarysearch'
dbg        = require('./utils').debug 'load'

# uncompress = require('compress-buffer').uncompress

IDX_AUTO_MASK       = 0x20
IDX_BASE_MASK       = 0x10
IDX_BYTE_COUNT_MASK = 0x07
DIFF_EQUAL  = 0
DIFF_INSERT = 1
DIFF_BASE   = 2
DIFF_DELETE = 3
DIFF_TYPE_MASK  = 0x30
DIFF_TYPE_SHIFT = 4
DIFF_COMPRESSED_MASK  = 0x40
DIFF_COUNT_CODE_MASK  = 0x0f

curPath = indexPath = dataPath = ''
index = []

getFileLen = (path) ->
  try
    stats = fs.statSync path
  catch e
    return 0
  stats.size

readUIntN = (n, buf, ofs) ->
  num = 0
  for i in [0...n]
    num *= 0x100
    num |= buf.readUInt8 ofs++, yes
  num

getDeltaHdr = (fdIn, fileOfs) ->
  buf = new Buffer 20
  fd = (if fdIn then fdIn else fs.openSync dataPath, 'r')
  fs.readSync fd, buf, 0, 20, fileOfs
  if not fdIn then fs.closeSync fd
  hdrByte = buf.readUInt8 0, yes
  lineNumLen = (hdrByte >>> 2) & 3
  charOfsLen =  hdrByte        & 3
  time    = buf.readUInt32BE 1, yes
  lineNum = readUIntN lineNumLen, buf, 1 + 4
  charOfs = readUIntN charOfsLen, buf, 1 + 4 + lineNumLen
  {time, lineNum, charOfs, hdrLen: 1 + 4 + lineNumLen + charOfsLen}

readIndexEntry = (idx, buf, pos) ->
  hdrByte    = buf.readUInt8 pos, yes
  isAuto     = ((hdrByte & IDX_AUTO_MASK) is IDX_AUTO_MASK)
  isBase     = ((hdrByte & IDX_BASE_MASK) is IDX_BASE_MASK)
  bytesInEnd = hdrByte & IDX_BYTE_COUNT_MASK
  fileBegPos = (if idx < 0 then 0 else index[idx].fileEndPos)
  fileEndPos = readUIntN bytesInEnd, buf, pos + 1
  entryLen   = 1 + bytesInEnd
  {isAuto, isBase, entryLen, fileBegPos, fileEndPos}

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
    # if compressed then diffDataBuf = uncompress diffDataBuf
    diffStr = diffDataBuf.toString()
  {diffType, diffStr, diffLen, diffDataLen}

processDeltas = (text, idx, idxInc, endIdx, baseIdx, baseDiffsBuf) ->
  fd = fs.openSync dataPath, 'r'
  diffsBufs = []
  loop
    if idx is baseIdx
        diffsBufs.push baseDiffsBuf
    else
      {fileBegPos, fileEndPos} = index[idx]
      {hdrLen, lineNum, charOfs} = getDeltaHdr fd, fileBegPos
      diffsLen = fileEndPos - fileBegPos - hdrLen - 4
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
      diffPos += diffLen
    text = nextText
  {text, lineNum, charOfs}

getTextAndPos = (idx, time) ->
  if index.length is 0 then return {text: '', index: -1, lineNum: 0, charOfs: 0}
  if time?
    idx = binSrch.closest index, time, (entry, tgt) -> load.getTime(entry.idx) - tgt
    if time < load.getTime(idx) then idx--
  if idx < 0 then return {text: '', index: -1, lineNum: 0, charOfs: 0}
  tgtIdx = endIdx = idx
  dist = 0
  loop
    dist = -dist
    if (baseEntry = index[endIdx + dist]) and baseEntry.isBase then break
    if dist <= 0 then dist--
  baseIdx = endIdx + dist
  {hdrLen, lineNum, charOfs} = getDeltaHdr null, baseEntry.fileBegPos
  baseDiffsLen = baseEntry.fileEndPos - baseEntry.fileBegPos - hdrLen - 4
  baseDiffsBuf = new Buffer baseDiffsLen
  fd = fs.openSync dataPath, 'r'
  fs.readSync fd, baseDiffsBuf, 0, baseDiffsLen, baseEntry.fileBegPos + hdrLen
  fs.closeSync fd
  baseText = readDiff(baseDiffsBuf, 0).diffStr
  if tgtIdx is baseIdx
    dbg 'getTextAndPos from base', baseIdx
    return {text: baseText, index: baseIdx, lineNum, charOfs, auto: baseEntry.isAuto}
  idxInc = (if dist < 0 then 1 else -1)
  idx = baseIdx
  if idxInc > 0 then idx++; endIdx++
  {text, lineNum, charOfs} =
    processDeltas baseText, idx, idxInc, endIdx, baseIdx, baseDiffsBuf
  if idxInc < 0
    {lineNum, charOfs} = getDeltaHdr null, index[tgtIdx].fileBegPos
  dbg 'getTextAndPos', tgtIdx, lineNum, charOfs
  {text, index: tgtIdx, lineNum, charOfs, auto: index[tgtIdx].isAuto}

setPath = (path) ->
  if path isnt curPath or 
      not fs.existsSync(path + '/data') or
      not fs.existsSync(path + '/index')
    curPath = path
    index = []

    # todo - refactor these two blocks
    if path
      mkdirp.sync path
      indexPath = pathUtil.join path, 'index'
      fs.closeSync fs.openSync indexPath, 'a'
      dataPath  = pathUtil.join path, 'data'
      fs.closeSync fs.openSync dataPath, 'a'
      indexBuf = fs.readFileSync indexPath
      pos = idx = 0
      while pos < indexBuf.length
        entry = readIndexEntry index.length-1, indexBuf, pos
        entry.idxFilePos = pos
        entry.idx        = idx++
        index.push entry
        pos += entry.entryLen

  if path
    lastEntry = index[index.length-1]
    if not lastEntry then indexSize = 0
    else indexSize = lastEntry.idxFilePos + lastEntry.entryLen
    fileSize  = getFileLen indexPath

    if indexSize < fileSize
      indexBuf = new Buffer fileSize - indexSize
      fd = fs.openSync indexPath, 'r'
      fs.readSync fd, indexBuf, 0, indexBuf.length, indexSize
      fs.closeSync fd
      pos = 0
      idx = (lastEntry?.idx ? -1) + 1
      while pos < indexBuf.length
        entry = readIndexEntry index.length-1, indexBuf, pos
        entry.idxFilePos = indexSize + pos
        entry.idx        = idx++
        index.push entry
        pos += entry.entryLen
      null

load = exports

load.getPath = (projPath, filePath) ->
  liveArchiveDir = projPath + '/.live-archive'
  if not fs.existsSync liveArchiveDir
    dbg 'no .live-archive dir in', projPath
    return {}
  projDirs = projPath.split /\/|\\/g
  path = liveArchiveDir + '/' + filePath.split(/\/|\\/g)[projDirs.length...].join('/')
  mkdirp.sync path
  try
    indexFileSize = fs.statSync(path + '/index').size
  catch e
    indexFileSize = 0
  {path, indexFileSize}

load.text = (projPath, filePath, idx, time) ->
  if not (path = load.getPath(projPath, filePath).path) then return {text: ''}
  setPath path
  idx ?= index.length - 1
  if idx < 0 then return {text: ''}
  getTextAndPos idx, time

load.getTime = (idx) -> 
  if index.length is 0 then return 0
  {time} = getDeltaHdr null, index[idx].fileOfsBeg
  time
  
load.lastTime = (path) ->
  setPath path
  lastIndex = (if index.length > 0 then index.length-1 else -1)
  {lastIndex}
