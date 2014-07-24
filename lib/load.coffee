
fs         = require 'fs'
pathUtil   = require 'path'
mkdirp     = require 'mkdirp'
binSrch    = require 'binarysearch'
# uncompress = require('compress-buffer').uncompress

IDX_BASE_MASK       = 0x10
IDX_BASE_SHIFT      = 4
IDX_BYTE_COUNT_MASK = 0x03
DIFF_EQUAL  = 0
DIFF_INSERT = 1
DIFF_BASE   = 2
DIFF_DELETE = 3
DIFF_SHIFT  = 4
DIFF_TYPE_MASK  = 0x30
DIFF_TYPE_SHIFT = 4
DIFF_COMPRESSED_MASK  = 0x40
DIFF_COMPRESSED_SHIFT = 6
DIFF_COUNT_CODE_MASK  = 0x0f

maxTextCacheAge  = 60 * 1000
maxTextCacheSize = 1e7

curPath = indexPath = dataPath = ''
index         = []
textCacheSize = 0

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

readUInt48 = (buf, ofs) ->
  ms16 = buf.readUInt16BE ofs,   yes
  ls32 = buf.readUInt32BE ofs+2, yes
  ms16 * 0x100000000 + ls32

readUIntN = (n, buf, ofs) ->
  num = 0
  for i in [0...n]
    num *= 0x100
    num |= buf.readUInt8 ofs++, yes
  num

readIndexEntry = (idx, buf, pos) ->
  hdrByte = buf.readUInt8 pos, yes
  isBase = ((hdrByte & IDX_BASE_MASK) is IDX_BASE_MASK)
  idxNumBytesInOfs = hdrByte & IDX_BYTE_COUNT_MASK
  saveTime   = readUInt48 buf, pos + 1
  fileEndPos = readUIntN idxNumBytesInOfs, buf, pos + 1 + 6
  entryLen   = 1 + 6 + idxNumBytesInOfs
  fileBegPos = (if idx is -1 then 0 else index[idx].fileEndPos)
  {isBase, saveTime, entryLen, fileBegPos, fileEndPos}

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

readBaseFromFile = (indexEntry) ->
  diffsLen = indexEntry.fileEndPos - indexEntry.fileBegPos - 12
  diffsBuf = new Buffer diffsLen
  fd = fs.openSync dataPath, 'r'
  fs.readSync fd, diffsBuf, 0, diffsLen, indexEntry.fileBegPos + 6
  fs.closeSync fd
  readDiff(diffsBuf, 0).diffStr

delCacheTextFromIndexEntry = (indexEntry) ->
  textCacheSize -= indexEntry.cacheText.length
  delete indexEntry.cacheText
  delete indexEntry.cacheTextUsedTime
  textCacheSize < maxTextCacheSize

pruneTextCache = ->
  now = Date.now()
  entries = []
  for indexEntry in index when indexEntry.cacheText
    usedTime = indexEntry.cacheTextUsedTime
    if usedTime < now - maxTextCacheAge
      if delCacheTextFromIndexEntry indexEntry then return
    else
      entries.push [usedTime, indexEntry]
  entries.sort()
  for entry in entries
      [usedTime, indexEntry] = entry
      if delCacheTextFromIndexEntry indexEntry then return
  null

addCacheTextToIndexEntry = (indexEntry, text) ->
  textCacheSize += textlength
  indexEntry.cacheText = text
  indexEntry.cacheTextUsedTime = Date.now()
  if textCacheSize > maxTextCacheSize then pruneTextCache()

chkSaveToCache = (idx, text) ->
  text

getText = (timeTgt) ->
  if index.length is 0 or timeTgt < index[0].saveTime then return ''
  endIdx = binSrch.closest index, timeTgt, (entry, tgt) -> entry.saveTime - tgt
  endIndexSaveTime = index[endIdx].saveTime
  if timeTgt < endIndexSaveTime
    endIdx--
    endIndexSaveTime = index[endIdx].saveTime
  dist = 0
  loop
    dist = -dist
    if (entry = index[endIdx + dist]) and (entry.cacheText or entry.isBase) then break
    if dist <= 0 then dist--
  if not (text = entry.cacheText) then text = readBaseFromFile entry
  if dist is 0 then return chkSaveToCache endIdx, text
  idxInc = (if dist < 0 then 1 else -1)
  idx = endIdx + dist
  if idxInc > 0 then idx++; endIdx++
  diffsBufs = []
  fd = fs.openSync dataPath, 'r'
  loop
    {fileBegPos, fileEndPos} = index[idx]
    diffsLen = fileEndPos - fileBegPos - 12
    diffsBuf = new Buffer diffsLen
    fs.readSync fd, diffsBuf, 0, diffsLen, fileBegPos + 6
    diffsBufs.push diffsBuf
    if (idx += idxInc) is endIdx then break
  fs.closeSync fd
  cachecount = 0
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
  chkSaveToCache endIdx, text

setPath = (path) ->
  if path isnt curPath
    curPath = path
    index = []
    textCacheSize = 0

    if path
      mkdirp.sync path
      indexPath = pathUtil.join path, 'index'
      fs.closeSync fs.openSync indexPath, 'a'
      dataPath  = pathUtil.join path, 'data'
      fs.closeSync fs.openSync dataPath, 'a'
      indexBuf = fs.readFileSync indexPath
      pos = 0
      while pos < indexBuf.length
        entry = readIndexEntry index.length-1, indexBuf, pos
        entry.idxFilePos = pos
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
      while pos < indexBuf.length
        entry = readIndexEntry index.length-1, indexBuf, pos
        entry.idxFilePos = indexSize + pos
        index.push entry
        pos += entry.entryLen
      null

load = exports

load.getPath = (projPath, filePath) ->
  projPath = pathUtil.resolve projPath
  filePath = pathUtil.resolve filePath

  liveArchiveDir = projPath + '/.live-archive'
  try
    fs.statSync liveArchiveDir
  catch e
    console.log 'no .live-archive dir in', projPath
    return
  projDirs = projPath.split /\/|\\/g
  path = liveArchiveDir + '/' + filePath.split(/\/|\\/g)[projDirs.length...].join('/')
  mkdirp.sync path
  path

load.text = (projPath, filePath, saveTime = Infinity) ->
  path = load.getPath projPath, filePath
  setPath path
  getText saveTime
