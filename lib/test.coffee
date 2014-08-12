			continue

		# for ceil display
		if room in ['tvRoom', 'acLine'] and
				getStats.glblStats.master?.avgTemp and
				getStats.glblStats.acLine?.avgTemp
			fs.writeFileSync 'data/house-temp-realtime.txt',
							  getStats.glblStats.master.avgTemp.toFixed(1) + ',' +
							  getStats.glblStats.acLine.avgTemp.toFixed(0)

		# for plotting
		date = new Date()
		secs = date.getSeconds()
		if Math.floor(secs/30) isnt lastSecs and
				getStats.glblStats.master?.avgTemp and
				getStats.glblStats.acLine?.avgTemp and
				getStats.glblStats.tvRoom?.avgTemp and
				getStats.glblStats.kitchen?.avgTemp and
				getStats.glblStats.guest?.avgTemp
			lastSecs = Math.floor(secs/30)

			runStates = ''
			for room2 in cmd.rooms()
				runStates += (if getStats.glblStats[room2].active  then ',1' else ',0')

			fs.appendFileSync 'data/house-temp-history.csv',
							(Math.floor(Date.now()/30000) - 46719359) + ',' +
							getStats.glblStats.acLine.avgTemp.toFixed(3) + ',' +
							getStats.glblStats.tvRoom.avgTemp.toFixed(3) + ',' +
							getStats.glblStats.kitchen.avgTemp.toFixed(3) + ',' +
							getStats.glblStats.master.avgTemp.toFixed(3) + ',' +
							getStats.glblStats.guest.avgTemp.toFixed(3) +
							runStates + '\n'

		threshold = switch
			when stat.mode is 'heat' then stat.heatSetting +
					(if stat.heating then +1 else -1) * hysteresis
			when stat.mode is 'cool' then stat.coolSetting +
					(if stat.cooling then -1 else +1) * hysteresis
			else 0

#		console.log 'threshold', threshold, stat

		stat.fanning = stat.heating = stat.cooling = no

		if ctrl.sysMode is 'heat' and stat.mode is 'heat' and stat.avgTemp < threshold
			stat.heating = yes
			hvacMode = 'heat'
			dampers &= ~parseInt cmd.roomMask[room], 16

		if ctrl.sysMode is 'cool' and stat.mode is 'cool' and stat.avgTemp > threshold and
														  not acDelaying()
			stat.cooling = yes
			hvacMode = 'cool'
			dampers &= ~parseInt cmd.roomMask[room], 16

		if ctrl.sysMode is 'fan' and stat.mode is 'fan'
			stat.fanning = true
			hvacMode = 'fan'
			dampers &= ~parseInt cmd.roomMask[room], 16

		if room is 'acLine'
			atmp = stat.avgTemp
			if (neg = (atmp < 0)) then atmp *= -1
			tempStr = (if neg then '-' else '') + Math.floor atmp
			while tempStr.length < 2 then tempStr = ' ' + tempStr
			pwsData = fs.readFileSync('/Cumulus/realtime.txt', 'utf8').split ' '
			logRooms.push tempStr + ' ' +
										Math.round(getStats.glblStats.intake.avgTemp) + '-' +
										Math.round(pwsData[2])

		else logRooms.push room[0].toUpperCase() + ':' +
				(stat.mode?[0] ? '-').toUpperCase() +
				(if stat.active then getHvacState() else '-') + ' ' +
				stat.avgTemp.toFixed(1) + ' ' +
				if threshold is 0 then '--.-'
				else threshold.toFixed(1)

#		dbData[room] = stat

	logStr = logRooms.join '   '
	if logStr[13..] isnt lastLogStr?[13..] and logStr.indexOf('NaN') is -1
		if (mins = new Date().getMinutes()) isnt blankLineMins
			blankLineMins = mins

			line = blnks(47)
			for room2 in cmd.rooms()
				stat = getStats.glblStats[room2]
				diff = stat.avgTemp - stat.lastAvgTemp ? 0
				if Math.abs(diff) < 0.05 then line += '    '
				else
					diff = diff.toFixed(1)
					while diff.length < 4 then diff = ' ' + diff
					line += diff
				line += blnks(13)
				stat.lastAvgTemp = stat.avgTemp
			console.log line
			console.log()

		hdr = ctrl.sysMode.toUpperCase()[0] + getHvacState() +
					(if extIntake then 'E' else 'I') +
					(if acDelaying() then 'D' else ' ') + ' '

		lastLogStr = logStr

#		pwsData = fs.readFileSync('/Cumulus/realtime.txt', 'utf8').split ' '
#		pws =
#			temp: 		+pwsData[2]
#			hum: 		+pwsData[3]
#			avgWind: 	+pwsData[5]
#			gust: 		+pwsData[40]
#
#		ctrl.logSeq += 1
#
#		dbData =
#			type:    'stats'
#			time:    Date.now()
#			seq:	 ctrl.logSeq
#			sysMode: ctrl.sysMode
#			pws: 	 pws
#		intakeTempC = getStats.glblStats.intake.avgTemp
#		dbData.intake = temp: (if intakeTempC then intakeTempC * (9/5) + 32)
#
#		_.extend dbData, getStats.glblStats
#		dbData.acLine = temp: dbData.acLine.temp, avgTemp: dbData.acLine.avgTemp
#		logDb.insert dbData

	if room is 'acLine' then cb?(); return

	if hvacMode is 'cool' then lastAc = now
	if now > lastAc + acFanOffDelay * 60000  then lastAc = 0

	if (lastAc or ctrl.sysMode is 'cool') and hvacMode isnt 'cool'
		dampers = 15
		for room2 in cmd.rooms()
			if stats[room2].mode in ['fan', 'cool']
				dampers &= ~parseInt cmd.roomMask[room2], 16
		if dampers is 15 then dampers = 0
		hvacMode = 'fan'

	if startAcMelt 
		startAcMelt = no
		hvacMode = 'fan'

	tempDiff = getStats.glblStats.inta ke.avgTemp - pwsData[2]
	if extIntake and (tempDiff < lowIntExtTempDiff)
		extIntake = off
	else if not extIntake and (tempDiff > highIntExtTempDiff)
		extIntake = on

	for room2 in cmd.rooms()
		isOn = ((dampers & parseInt(cmd.roomMask[room2], 16)) is 0)
		getStats.glblStats[room2].active = isOn

	cmd.dampersCmd dampers, (err) ->
		if err
			#dbg 'dampersCmd err', err
			hvac.appState = 'closing'
			cmd.allCtrlOff()
			process.exit 1
			return

		# cmd.hvacModeCmd hvacMode, false, cb
		cmd.hvacModeCmd hvacMode, extIntake, cb

		if acOn and hvacMode isnt 'cool' then lastAcOff = now
		acOn = (hvacMode is 'cool')
