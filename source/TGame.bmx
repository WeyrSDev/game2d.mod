

'this global is set by the New() method of TGame.
Global G_CURRENTGAME:TGame

Rem
	bbdoc: State based game for game2d.
	about: Add user setup code in a StartUp() method when extending this type.
	States are added by calling AddGameState()
	Start the game by calling Start()
	User cleanup code is run on shutdown by adding a CleanUp() method to the extended type.
end rem
Type TGame

	'#region setup
	'---------------------------------------------------------

	'the game title. Appears in the window title.
	Field _title:String

	'sound channels
	Field _soundChannels:TChannel[]

	'collection of game states, by index.
	Field _gameStates:TBag

	'The active game state.
	Field _currentGameState:TState

	'The state we're going to.
	Field _nextGameState:TState

	'The transition to use when leaving current state.
	Field _leaveTransition:TTransition

	'The transition to use when entering the next state.
	Field _enterTransition:TTransition

	'statistics
	Field _startTime:Int
	Field _updates:Int
	Field _framesRendered:Int

	'bools
	Field _paused:Int
	Field _running:Int
	Field _vsync:Int

	'configuration file
	field _iniFile:TINIFile

	'game font is rendered at this scale. default is 1.0
	Field _fontScale:Float
	field _gameFont:TImageFont

	'fixed game step timer
	Field _timer:TFixedTime

	'menu backdrop color
	field menuR:int, menuG:int, menuB:Int


	'audio driver name
	Field audioDriverName:String


	Method New()

		'set helper global reference
		G_CURRENTGAME = Self

        _fontScale = 1.00000
		_timer = New TFixedTime
        _gameStates = New TBag

        Self.menuR = 10
        Self.menuG = 10
        Self.menuB = 10

        'create managers
        TResourceManager.GetInstance()
        TEntityManager.GetInstance()
        TInputManager.GetInstance()
        TGfxManager.GetInstance()

		Self.LoadConfig()

		'apply or set default settings to managers
		TGfxManager.GetInstance().SetDefaultValues( _iniFile )

		'create sound channels and set audio drivers
		Self.SetupSound()

		Self.SetTitle("Powered by Game2d!")
	End Method


	Rem
		bbdoc: Runs user setup code and starts the game.
		about: User setup code is be added to the StartUp() method.
	endrem
	Method Start()

		'run user setup code
		Self.Startup()

		'set running flags
		_running = True
		_paused = False
		_vsync = 1'-1

		'reset statistics
		_startTime = MilliSecs()
		_framesRendered = 0
		_updates = 0

		'reset the step timer
		_timer.Reset()

		'run the Enter() method in the default state
		'otherwise this never gets called!
		_currentGameState.Enter()

		'enter the run loop
		Self.Run()
	End Method



	Rem
		bbdoc: Sets game name
	endrem
	Method SetTitle( newName:String )
		?Debug
			newName:+" - debug build"
		?
		_title = newName
		AppTitle = newName
	End Method


	Rem
		bbdoc: Returns game name
		returns: String
	endrem
	Method GetTitle:String()
		Return _title
	End Method


	Method GetConfig:TINIFile()
		return _iniFile
	EndMethod


	'#endregion

	'#region configuration
	'------------------------------------------------------------------

	Rem
		bbdoc:   Loads the game config file, located in the exe path
		about:   The name for the config file is "config.ini" and
				 it is located in the game executable directory.
		returns:
	EndRem
	Method LoadConfig()
		_iniFile = TINIFile.Create( AppDir + "/config.ini")
		_iniFile.Load()
		_iniFile.CreateMissingEntries(True)
	End Method


	Rem
		bbdoc:   Saves the settings in the ini file to disk.
		about:   Managers put their values in the ini file before saving.
		returns:
	EndRem
	Method SaveConfig()

		' save audio driver string
		_iniFile.SetStringValue("Audio", "Drivername", Self.audioDriverName )

		TInputManager.GetInstance().ToIniFile( _iniFile )
		TGfxManager.GetInstance().ToIniFile( _iniFile )
		_iniFile.Save()
	End Method

	'#endregion

	'#region sound
	'------------------------------------------------------------------

	Rem
		bbdoc:   Sets up the sound system
		about:   This method is called by TGame.Start()
		returns:
	EndRem
    Method SetupSound()

		'enable openal audio
		'to add it to the list of possible audio drivers
		EnableOpenALAudio()

		Local audioSet:Int = False

		'get audio driver string from ini file
		Self.audioDriverName = _iniFile.GetStringValue("Audio", "Drivername")
		'try to set that driver
		If Not SetAudioDriver(self.audioDriverName)

			'no succes.
			'scan system for audio drivers and attempt to set.

			' get a list of available audio drivers
			Local arr:String[] = AudioDrivers()

			' try to set audiodriver to one of the found drivers
			For Local index:Int = 0 Until arr.Length
				If SetAudioDriver(arr[index]) = True
					audioSet = True

					'save name so it can be added to ini file later on
					Self.audioDriverName = arr[index]
					Exit
				EndIf
			Next

			If Not audioSet Then RuntimeError("Error: Cannot set audio driver.")
		endif

		Self.AllocateChannels()
    End Method


	'allocate 64 channels.
    Method AllocateChannels()
		_soundChannels = New TChannel[64]
		For Local index:Int = 0 Until _soundChannels.Length
			_soundChannels[index] = AllocChannel()
		Next
    EndMethod


    'stops all sound playing
    'and destroys audio driver
    Method CleanUpSound()
		For Local index:Int = 0 Until _soundChannels.Length
			Local channel:TChannel = _soundChannels[index]
			channel.Stop()
		Next
		SetAudioDriver( Null )
    EndMethod


	Method PlayGameSound:TChannel(soundName:String, groupName:String, volume:Float, rate:float, channel:TChannel=Null)
		If channel = Null
			'find a free channel
			For Local index:Int = 0 Until _soundChannels.Length
				Local c:TChannel = _soundChannels[index]

				if c = null then DebugLog("index " + index+ " is not a channel")

				If Not c.Playing()
					channel = c

					DebugLog( "channels available " + _soundChannels.Length )
					debuglog "using channel " + index

					Exit
				EndIf
			Next

			'overload.
			If channel = Null
				debuglog "no sound channel available!"
				return Null' channel = _soundChannels[0]
			EndIf

		EndIf

		local sound:TSound = TResourceManager.GetInstance().GetSound( soundName, groupName )

		'play sound
		SetChannelVolume( channel, 0.0 )
		CueSound( sound, channel )
		SetChannelVolume( channel, volume )
		SetChannelRate( channel, rate )
		ResumeChannel(channel)
		Return channel
	End Method



	Rem
		bbdoc: Stops all sound channels.
	endrem
	Method StopAllSound()
		For Local index:Int = 0 Until _soundChannels.Length
			Local channel:TChannel = _soundChannels[index]
			If channel.Playing() Then channel.SetPaused(true)
		Next
	End Method

	'#endregion


	'#region input
	'------------------------------------------------------------------

	'adds a key control to the input device
	'uses value in ini file if it exists
'	Method AddKeyControl(c:TKeyControl)
'		TInputManager.GetInstance().AddKeyControl(c)
'
'		if _iniFile.ParameterExists("Input", c.GetName())
'			c.SetKey( _iniFile.GetIntValue("Input", c.GetName()) )
'		endif
'	End Method


	'#endregion

	'#region runtime
	'------------------------------------------------------------------

	'main loop. called by Start()
	Method Run()

		local lastUpdate:Int = _updates

		While _running = True
			If Not _paused
				_timer.Update()
				While _timer.TimeStepNeeded()
					Self.Update(_timer.GetDeltaTime())
					_updates:+ 1
				Wend

				If KeyHit(KEY_ESCAPE) and not TInputManager.GetInstance().IsConfiguring()
					Self.SetPaused(True)
					FlushKeys()
				endif

			'paused means that menu is up and keys for menu navigation should be scanned
			else
				If TInputManager.GetInstance().IsConfiguring()
					TInputManager.GetInstance().Update()
				else
					Select True
						Case KeyHit(KEY_ESCAPE)
							Self.SetPaused(False)
							FlushKeys()
							_timer.Reset()
						Case KeyHit(KEY_F10)
							TInputManager.GetInstance().StartAudioConfig()
							FlushKeys()
						Case KeyHit(KEY_F11)
							TGfxManager.GetInstance().ToggleWindowed()
							FlushKeys()
						Case KeyHit(KEY_F12)
							TInputManager.GetInstance().StartConfiguring()
							FlushKeys()
						Case KeyHit(KEY_Q)
							Self.RequestStop()
						Case KeyHit(KEY_R)
							Self.SetPaused(False)
							FlushKeys()
							Self.OnRestartGame()
					EndSelect
				EndIf
			endif

			if KeyHit(KEY_INSERT) then TakeScreenShot()

			Cls
			Self.Render(_timer.GetTweening())
			Flip(_vsync)

			If AppTerminate() Then Self.RequestStop()
		Wend
		Self.Stop()
	End Method


	'game logic update. Called by Run()
	Method Update(delta:Double)
		If _leaveTransition
			_leaveTransition.Update(delta)
			If _leaveTransition.IsComplete()
				_currentGameState.Leave()
				_currentGameState = _nextGameState
				_nextGameState = Null
				_leaveTransition = Null
				_currentGameState.Enter()
				If _enterTransition Then _enterTransition.Initialize()
			Else
				Return
			End If
		End If
		If _enterTransition
			_enterTransition.Update(delta)
			If _enterTransition.IsComplete()
				_enterTransition = Null
			Else
				Return
			End If
		End If

		_currentGameState.PreUpdate(delta)
		_currentGameState.Update(delta)
		TInputManager.GetInstance().Update()
		TEntityManager.GetInstance().Update()
		_currentGameState.PostUpdate(delta)
	End Method


	Rem
		bbdoc:   Stops the game.
		about:   Gets called when the game is stopped.
		returns:
	EndRem
	Method Stop()

		'run user cleanup code
		Self.CleanUp()

		Self.SaveConfig()

		_gameStates.Clear()

		_timer = Null

		Self.StopAllSound()
		Self.CleanUpSound()

		'get rid of managers
		TEntityManager.GetInstance().Destroy()
		TResourceManager.GetInstance().Destroy()
		TGfxManager.GetInstance().Destroy()
		TInputManager.GetInstance().Destroy()

		ShowMouse()
	End Method


	Rem
		bbdoc:   Calls the onrestartgame method in the current state
		about:   Also unpauses the game.
		returns:
	EndRem
	Method OnRestartGame()
		Self.SetPaused(False)
		FlushKeys()

		'run user code
		_currentGameState.OnRestartGame()
	EndMethod



	Rem
		bbdoc: Returns true when game is transitioning between states.
		returns: Int
	endrem
	Method Transitioning:Int()
		Return _enterTransition Or _leaveTransition <> Null
	End Method


	Rem
		bbdoc: Returns game state by specified ID.
		returns: TState
	endrem
	Method GetGameStateByID:TState(id:Int)
		Return TState(_gameStates.Get(id))
	End Method


	Rem
		bbdoc: Enters a gamestate with the provided transitions.
	endrem
	Method EnterState(id:Int, enter:TTransition = Null, leave:TTransition = Null)
		If Not enter Then enter = New TTransitionEmpty
		If Not leave Then leave = New TTransitionEmpty
		_enterTransition = enter
		_leaveTransition = leave

		_nextGameState = GetGameStateByID(id)
		If Not _nextGameState Then RuntimeError "Cannot find state with id:" + id

		_leaveTransition.Initialize()
	End Method


	Rem
		bbdoc: Adds state to this game with specified id.
		about: First state added is the default state when the game starts.
	endrem
	Method AddGameState(gameState:TState, id:Int)
		_gameStates.Set(id, gameState)
		gameState.SetId(id)
		gameState.SetGame(Self)
		If Not _currentGameState Then _currentGameState = gameState
	End Method


	Rem
	bbdoc: Sets engine pause mode.
	endrem
	Method SetPaused(bool:Int)
		_paused = bool
	End Method


	Rem
	bbdoc: Returns true when the engine is paused.
	endrem
	Method IsPaused:Int()
		Return _paused
	End Method


	Rem
		bbdoc: Calling this will stop the game on the next update.
	endrem
	Method RequestStop()
		_running = False
	End Method


	Rem
		bbdoc: Sets game update frequency, in times per second.
	endrem
	Method SetUpdateFrequency(frequency:Int)
		_timer.SetUpdateFrequency(frequency)
	End Method

	'#endregion	runtime


	'#region graphics and render
	'---------------------------------------------------


	Method Render(tween:Double)
		_currentGameState.PreRender(tween)

		TEntityManager.GetInstance().Render(tween)

		_currentGameState.Render(tween)

		'display pause menu
		'but not when configuring controls
		if IsPaused() and TInputManager.GetInstance().IsConfiguring() = false
			TRenderState.Push()
			TRenderState.Reset()

			'take virtual resolution offset into account
			SetOrigin(TVirtualGfx.VG.vxoff, TVirtualGfx.VG.vyoff)

			'menu border
			'get y size of border, 8 lines, extra padding of 4 pixels
			local fontheight:Int = Self.GetGameFontSize()
			local boxheight:Int = 4 +(8 * fontheight)

			'center
			local ypos:Int = GameHeight() / 2 - (boxheight/2)
			SetColor(menuR, menuG, menuB)
			SetAlpha(0.90)
			DrawRect(5, ypos, GameWidth()-10, boxheight )

			'draw text
			SetAlpha(1.0)
			SetGameColor( CYAN )
			ypos:+2
			RenderText("Game Menu", 0, ypos, true)
			ypos:+fontheight+4
			SetGameColor( WHITE )
			RenderText("[ESCAPE] Continue", 0, ypos, true)
			ypos:+fontheight
			RenderText("[R] Restart", 0, ypos, true)
			ypos:+fontheight
			RenderText("[Q] Quit", 0, ypos, true)
			ypos:+fontheight+4'fontheight
			RenderText("[F10] View/Set Audiodriver",0,ypos, true)
			ypos:+fontheight
			RenderText("[F11] Fullscreen/Window",0,ypos, true)
			ypos:+fontheight
			RenderText("[F12] View/Configure Controls", 0, ypos, true)
		EndIf

		TInputManager.GetInstance().Render()

		TRenderState.Pop()

		If _leaveTransition
			_leaveTransition.Render()
		ElseIf _enterTransition
			_enterTransition.Render()
		EndIf

		_currentGameState.PostRender(tween)
	End Method


	Rem
		bbdoc:   Sets game menu backdrop color.
		about:
		returns:
	EndRem
	Method SetMenuBackdropColor(r:int, g:int, b:int)
		menuR = r
		menuB = b
		menuG = g
	End Method


	Rem
		bbdoc:   Gets menu colors to passed variables.
		about:
		returns:
	EndRem
	Method GetMenuBackdropColor(r:int var, g:int var, b:int var)
		r = menuR
		g = menuG
		b = menuB
	End Method


	Rem
		bbdoc: Sets vertical blank flag.
	endrem
	Method SetVSync(bool:Int)
		_vsync = bool
	End Method


	Rem
		bbdoc: Returns vertical blank flag.
		returns: Int
	endrem
	Method GetVSync:Int()
		Return _vsync
	End Method



	Method SetGameFont( font:TImageFont )', size:Int )
		SetImageFont( font )
		_gameFont = font
	End Method


	Method GetGameFontSize:Int ()
		return _gameFont.Height() * _fontScale
	EndMethod


	Method GetGameFont:TImageFont()
		return _gameFont
	End Method


	Rem
		bbdoc:   Sets game font scale.
		about:
		returns:
	EndRem
	Method SetGameFontScale(value:Float)
		_fontScale = value
	EndMethod


	Rem
		bbdoc:   Returns game font scale.
		returns: Float
	EndRem
	Method GetGameFontScale:Float()
		Return _fontScale
	EndMethod

	'#endregion graphics and render


	'#region user hooks
	'----------------------------------------------------------

	Rem
		bbdoc: User hook to perform game startup logic.
		about: This method is called when the game starts.
	endrem
	Method Startup()
	End Method


	Rem
		bbdoc: User hook to perform game shut down logic.
		about: This method is called when the game stops.
	endrem
	Method CleanUp()
	End Method

	'#endregion  user hooks

End Type

' --------------------------------------------------

Function SetGameFont( f:TImagefont )
	G_CURRENTGAME.SetGameFont( f )
EndFunction


Function GetGameFont:TImageFont()
	return G_CURRENTGAME.GetGameFont()
EndFunction


Function GetGameFontSize:Int()
	return G_CURRENTGAME.GetGameFontSize()
EndFunction


Function GameTransitioning:Int()
	Return G_CURRENTGAME.Transitioning()
EndFunction


Function SetGameTitle( name:String )
	G_CURRENTGAME.SetTitle( name )
EndFunction


Function AddGameState( state:TState, stateID:Int)
	G_CURRENTGAME.AddGameState( state, stateID )
EndFunction


Function EnterGameState( stateid:Int, fadein:TTransition, fadeout:TTransition )
	G_CURRENTGAME.EnterState( stateid, fadein, fadeout )
EndFunction


Function PlayGameSound:TChannel(soundName:String, groupName:String, volume:Float = 1.0, rate:float = 1.0, channel:TChannel = null )
	return G_CURRENTGAME.PlayGameSound:TChannel( soundName, groupName, volume, rate, channel )
EndFunction


Function StopAllSound()
	G_CURRENTGAME.StopAllSound()
End Function
