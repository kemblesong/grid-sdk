--========= Copyright © 2013-2016, Planimeter, All rights reserved. ==========--
--
-- Purpose: Console class
--
--============================================================================--

-- UNDONE: The gui subsystem will load gui.console again here just by indexing
-- it the first time around, so we can't persist commandHistory in debug
-- local commandHistory = gui.console and gui.console.commandHistory or {}

require( "engine.client.gui.console.consoletextbox" )
require( "engine.client.gui.console.consoletextboxautocompleteitemgroup" )

class "console" ( gui.frame )

function console.print( ... )
	local args = { ... }
	for i = 1, select( "#", ... ) do
		args[ i ] = tostring( args[ i ] )
	end
	g_Console.output:insertText( table.concat( args, "\t" ) .. "\n" )
end

local function doConCommand( command, argString, argTable )
	concommand.dispatch( localplayer, command, argString, argTable )
end

local function doConVar( command, argString )
	if ( argString ~= "" ) then
		if ( string.utf8sub( argString,  1,  1 ) == "\"" and
			 string.utf8sub( argString, -1, -1 ) == "\"" ) then
			argString = string.utf8sub( argString, 2, -2 )
		end
		convar.setConvar( command, argString )
	else
		local convar     = convar.getConvar( command )
		local name       = convar:getName()
		local value      = convar:getValue()
		local helpString = convar:getHelpString() or ""
		local default    = convar:getDefault()    or ""
		if ( default ~= "" ) then
			default = "(Default: \"" .. default .. "\")\n"
		end
		print( name .. " = \"" .. value .. "\" " .. default .. helpString )
	end
end

local function doCommand( self, input )
	self.input:setText( "" )
	print( "] " .. input )

	local command = string.match( input, "^([^%s]+)" )
	if ( not command ) then
		return
	end

	local _, endPos = string.find( input, command, 1, true )
	local argString = string.trim( string.utf8sub( input, endPos + 1 ) )
	local argTable  = string.parseargs( argString )
	if ( concommand.getConcommand( command ) ) then
		doConCommand( command, argString, argTable )
	elseif ( convar.getConvar( command ) ) then
		doConVar( command, argString )
	else
		print( "'" .. command .. "' is not recognized as a console command " ..
		       "or variable." )
	end
end

-- console.commandHistory = commandHistory
console.commandHistory = {}

local function autocomplete( text )
	if ( text == "" ) then
		return nil
	end

	local suggestions = {}

	for command in pairs( concommand.concommands ) do
		if ( string.find( command, text, 1, true ) == 1 and
		     not table.hasvalue( gui.console.commandHistory, command ) ) then
			table.insert( suggestions, command .. " " )
		end
	end

	for command, convar in pairs( convar.convars ) do
		if ( string.find( command, text, 1, true ) == 1 ) then
			table.insert( suggestions, command .. " " .. convar:getValue() )
		end
	end

	table.sort( suggestions )

	for i, history in ipairs( gui.console.commandHistory ) do
		if ( string.find( history, text, 1, true ) == 1 ) then
			table.insert( suggestions, 1, history )
		end
	end

	local name = string.match( text, "^([^%s]+)" )
	local command = concommand.getConcommand( name )
	local shouldAutocomplete = string.find( text, name .. " ", 1, true )
	if ( command and shouldAutocomplete ) then
		local _, endPos = string.find( text, name, 1, true )
		local argS = string.trim( string.utf8sub( text, endPos + 1 ) )
		local argT = string.parseargs( argS )
		local autocomplete = command:getAutocomplete( argS, argT )
		if ( autocomplete ) then
			local t = autocomplete( argS, argTable )
			if ( t ) then
				table.prepend( suggestions, t )
			end
		end
	end

	return #suggestions > 0 and suggestions or nil
end

local keypressed = function( itemGroup, key, isrepeat )
	if ( key ~= "delete" ) then
		return
	end

	-- BUGBUG: We never get here anymore due to the introduction of
	-- cascadeInputToChildren.
	local commandHistory = gui.console.commandHistory
	for i, history in ipairs( commandHistory ) do
		if ( itemGroup:getValue() == history ) then
			table.remove( commandHistory, i )
			local item = itemGroup:getSelectedItem()
			itemGroup:removeItem( item )
			return
		end
	end
end

function console:console()
	local name = "Console"
	gui.frame.frame( self, g_MainMenu or g_RootPanel, name, "Console" )
	self.width     = point( 661 )
	self.minHeight = point( 178 )

	self.output = gui.consoletextbox( self, name .. " Output Text Box", "" )
	self.input  = gui.textbox( self, name .. " Input Text Box", "" )
	self.input.onEnter = function( textbox, text )
		text = string.trim( text )
		doCommand( self, text )

		local commandHistory = gui.console.commandHistory
		if ( not table.hasvalue( commandHistory, text ) and text ~= "" ) then
			table.insert( commandHistory, text )
		end
	end

	if ( not _INTERACTIVE ) then
		local input = self.input
		input:setAutocomplete( autocomplete )
		name = name .. " Autocomplete Item Group"
		local autocompleteItemGroup = gui.consoletextboxautocompleteitemgroup
		input.autocompleteItemGroup = autocompleteItemGroup( self.input, name )
		input.autocompleteItemGroup.keypressed = keypressed
	end

	self:invalidateLayout()

	if ( _INTERACTIVE ) then
		self:doModal()
	end
end

function console:activate()
	self:invalidate()
	gui.frame.activate( self )
	gui.setFocusedPanel( self.input, true )
end

function console:drawBackground( color )
	if ( _INTERACTIVE ) then
		return
	end

	gui.panel.drawBackground( self, color )
end

function console:invalidateLayout()
	local width  = self:getWidth()
	local height = self:getHeight()
	local margin = gui.scale( 36 )
	if ( not self:isResizing() ) then
		local parent = self:getParent()
		if ( not _INTERACTIVE ) then
			self:setPos( parent:getWidth() - width - margin, margin )
		else
			self:setPos( 0, 0 )
		end
	end

	margin = point( 36 )
	local titleBarHeight = point( 86 )
	self.output:setPos( margin, titleBarHeight )
	self.output:setWidth( width - 2 * margin )

	self.input:setPos( margin, height - self.input:getHeight() - margin )
	self.input:setWidth( width - 2 * margin )

	gui.frame.invalidateLayout( self )
end

gui.register( console, "console" )

local con_enable = convar( "con_enable", "0", nil, nil,
                           "Allows the console to be activated" )

concommand( "toggleconsole", "Show/hide the console", function()
	local mainmenu = g_MainMenu
	local console  = g_Console
	if ( not mainmenu:isVisible() and
	         console:isVisible()  and
	         con_enable:getBoolean() ) then
		mainmenu:activate()
		console:activate()
		return
	end

	if ( console:isVisible() ) then
		console:close()
	else
		if ( not con_enable:getBoolean() ) then
			return
		end

		if ( not mainmenu:isVisible() ) then
			mainmenu:activate()
		end

		console:activate()
	end
end )

concommand( "clear", "Clears the console", function()
	if ( _WINDOWS ) then
		-- This breaks the LOVE console. :(
		-- os.execute( "cls" )
	else
		os.execute( "clear" )
	end

	if ( g_Console ) then
		g_Console.output:setText( "" )
	end
end )

concommand( "echo", "Echos text to console",
	function( _, _, _, argS, argT )
		print( argS )
	end
)

concommand( "help", "Prints help info for the console command or variable",
	function( _, _, _, _, argT )
		local name = argT[ 1 ]
		if ( name == nil ) then
			print( "help <console command or variable name>" )
			return
		end

		local command = concommand.getConcommand( name ) or
		                convar.getConvar( name )
		if ( command ) then
			print( command:getHelpString() )
		else
			print( "'" .. name .. "' is not a valid console command or " ..
			       "variable." )
		end
	end
)

if ( g_Console ) then
	local visible = g_Console:isVisible()
	local output  = g_Console.output:getText()
	g_Console:remove()
	g_Console = nil
	g_Console = gui.console()
	g_Console.output:setText( output )
	if ( visible ) then
		g_Console:activate()
	end
end
