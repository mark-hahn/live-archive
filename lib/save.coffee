
fs       = require 'fs'
pathUtil = require 'path'
mkdirp   = require 'mkdirp'
load     = require './load'

DIFF_BASE = 2
checkFiles     = require './checkFiles'
{diff_match_patch, DIFF_DELETE, DIFF_INSERT, DIFF_EQUAL} =
                      require '../vendor/diff_match_patch_uncompressed.js'
diffMatchPatch = new diff_match_patch
diff_match = new diff_match_patch

saveTime = 0
curPath = curText = indexPath = dataPath = ''

writeUInt48 = (num, buf, ofs) ->
  ms16 = (num / 0x100000000) & 0xffff
  ls32 = num & 0xffffffff
  buf.writeUInt16BE ms16, ofs,   yes
  buf.writeUInt32BE ls32, ofs+2, yes

indexEntryLen = 20
writeIndexEntry = (saveTime, fileBegPos, fileEndPos, buf, ofs = 0) ->
  buf.writeUInt16BE    0,      ofs +  0
  writeUInt48   saveTime, buf, ofs +  2
  writeUInt48 fileBegPos, buf, ofs +  8
  writeUInt48 fileEndPos, buf, ofs + 14

diffHdrLen = 8
writeDiffHdr = (diffType, diffLen, buf, ofs = 0) ->
  buf.writeUInt8        0,      ofs + 0
  buf.writeInt8  diffType,      ofs + 1
  writeUInt48     diffLen, buf, ofs + 2

deltaEndFlagLen  = 6
deltaEndFlagByte = 0xff

getFileLen = (path) ->
  try
    stats = fs.statSync path
  catch e
    mkdirp.sync pathUtil.dirname path
    fs.closeSync fs.openSync path, 'a'
    return 0
  stats.size

appendDelta = (diffList) ->
  deltaLen = indexEntryLen
  for diff in diffList
    deltaLen += diffHdrLen
    [diffType, diffStr] = diff
    if diffType not in [DIFF_DELETE, DIFF_EQUAL]
      strBytesLen = Buffer.byteLength diffStr
      diff[2] = strBytesLen
      deltaLen += strBytesLen
  deltaLen += deltaEndFlagLen

  indexBuf = new Buffer indexEntryLen
  saveTime = Math.max saveTime + 3, Date.now()
  dataFileLen = getFileLen dataPath
  writeIndexEntry saveTime, dataFileLen, dataFileLen + deltaLen, indexBuf

  dataBuf = new Buffer deltaLen
  indexBuf.copy dataBuf
  pos = indexEntryLen
  for diff in diffList
    [diffType, diffStr, strBytesLen] = diff
    noStr = diffType in [DIFF_DELETE, DIFF_EQUAL]
    diffLen = (if noStr then diffStr.length else strBytesLen)
    writeDiffHdr diffType, diffLen, dataBuf, pos
    pos += diffHdrLen
    if not noStr
      dataBuf.write diffStr, pos, strBytesLen
      pos += strBytesLen
  dataBuf.fill deltaEndFlagByte, pos

  fs.appendFileSync  dataPath,  dataBuf
  fs.appendFileSync indexPath, indexBuf

setPath = (path) ->
  if path isnt curPath
    curPath = path
    curText = ''
    if path
      indexPath = pathUtil.join path, 'index'
      dataPath  = pathUtil.join path, 'data'
      curText   = load.text path

save = exports

save.text = (path, text, base = (curText is '')) ->
  if path is curPath and text is curText then return
  setPath path
  diffList = if base then [[DIFF_BASE, text]]   \
                     else diffMatchPatch.diff_main curText, text
  curText = text
  appendDelta diffList
  saveTime
