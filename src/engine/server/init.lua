--========= Copyright © 2013-2016, Planimeter, All rights reserved. ==========--
--
-- Purpose: Engine server interface
--
--============================================================================--

require( "engine.server.network" )
require( "engine.shared.network.payload" )

local concommand   = concommand
local convar       = convar
local debug        = debug
local getmetatable = getmetatable
local ipairs       = ipairs
local filesystem   = filesystem
local network      = engine.server.network
_G.networkserver   = network
local love         = love
local payload      = payload
local print        = print
local region       = region
local require      = require
local setmetatable = setmetatable
local string       = string
local table        = table
local tostring     = tostring
local unrequire    = unrequire
local _G           = _G

module( "engine.server" )

local function error_printer(msg, layer)
	print((debug.traceback("Error: " ..
	       tostring(msg), 1+(layer or 1)):gsub("\n[^\n]+$", "")))
end

function errhand(msg)
	msg = tostring(msg)

	error_printer(msg, 2)

	while true do
		if love.timer then
			love.timer.sleep(0.1)
		end
	end

end

function load( arg )
	local initialized = network.initializeServer()
	if ( not initialized ) then
		-- print( "Failed to initialize server!" )
		return false
	end

	require( "game" )

	_G.gameserver = require( "game.server" )
	_G.gameserver.load( arg )

	return true
end

function onConnect( event )
	print( tostring( event.peer ) .. " has connected." )
	onPostConnect( event )
end

local players = {}

local function getAccount( player, peer )
	for i, v in ipairs( players ) do
		if ( v.peer == peer ) then
			player.account = v.account
			table.remove( players, i )
		end
	end
end

function onPostConnect( event )
	-- Initialize region
	local region = _G.game.initialRegion
	_G.region.load( region )

	-- Initialize player
	require( "engine.shared.entities.player" )
	local player = _G.player.initialize( event.peer )
	player:setRegion( _G.region.getByName( region ) )

	player:onConnect()

	-- Set spawn point
	local spawnPoint = _G.gameserver.getSpawnPoint( player )
	local position = _G.vector.origin + _G.vector( 0, _G.game.tileSize )
	if ( spawnPoint ) then
		position = spawnPoint:getPosition()
	end
	player:setNetworkVar( "position", position )

	-- Send server info
	sendServerInfo( player )
end

local directoryWhitelist = {
	"regions"
}

local function onDownloadRequest( payload )
	local filename = payload:get( "filename" )
	if ( not filename ) then
		return
	end

	filename   = string.fixslashes( filename )
	local peer = payload:getPeer()

	print( tostring( peer ) .. " requested \"" .. filename .. "\"..." )

	if ( string.find( filename, "/..", 1, true ) or
	     string.ispathabsolute( filename ) ) then
		print( "Access denied to " .. tostring( peer ) .. "!" )
		return
	end

	if ( not filesystem.exists( filename ) ) then
		print( filename .. " does not exist!" )
		return
	end

	local directory = string.match( filename, "(.-)/" )
	if ( not directory or
	     not table.hasvalue( directoryWhitelist, directory ) ) then
		print( tostring( peer ) ..
		       " requested file outside of directory whitelist (" ..
		       directory .. ")!" )
		return
	end

	upload( filename, peer )
end

payload.setHandler( onDownloadRequest, "download" )

local sv_payload_show_receive = convar( "sv_payload_show_receive", "0", nil, nil,
                                        "Prints payloads received from clients" )

function onReceive( event )
	local payload = payload.initializeFromData( event.data )
	payload:setPeer( event.peer )

	if ( sv_payload_show_receive:getBoolean() ) then
		print( "Received payload \"" .. payload:getStructName() .. "\" from " ..
		       tostring( payload:getPeer() ) .. ":" )
		table.print( payload:getData(), 1 )
	end

	payload:dispatchToHandler()
end

function onDisconnect( event )
	local player = _G.player.getByPeer( event.peer )
	if ( player ) then
		player:onDisconnect()
		player:remove()
	end

	print( tostring( event.peer ) .. " has disconnected." )
end

local function sendEntities( player )
	local entities = _G.entity.getAll()
	for _, entity in ipairs( entities ) do
		if ( entity ~= player ) then
			local payload = payload( "entitySpawned" )
			payload:set( "classname", entity:getClassname() )
			payload:set( "entIndex", entity.entIndex )
			payload:set( "networkVars", entity:getNetworkVarTypeLenValues() )
			player:send( payload )
		end
	end
end

local function onReceiveClientInfo( payload )
	local player         = payload:getPlayer()
	local viewportWidth	 = payload:get( "viewportWidth" )
	local viewportHeight = payload:get( "viewportHeight" )
	player:setViewportSize( viewportWidth, viewportHeight )

	sendEntities( player )

	player:initialSpawn()
end

payload.setHandler( onReceiveClientInfo, "clientInfo" )

local function onReceiveConcommand( payload )
	local player    = payload:getPlayer()
	local name      = payload:get( "name" )
	local argString = payload:get( "argString" )
	if ( player == _G.localplayer ) then
		return
	end

	concommand.dispatch( player, name, argString, argTable )
end

payload.setHandler( onReceiveConcommand, "concommand" )

function quit()
	if ( _G.game and _G.game.server ) then
		 _G.game.server.shutdown()
		 _G.game.server = nil
	end

	unrequire( "game" )
	_G.game = nil

	network.shutdownServer()

	region.unloadAll()

	unrequire( "engine.server.network" )
	_G.networkserver = nil
	unrequire( "engine.server" )
	_G.serverengine = nil
end

function sendServerInfo( player )
	local payload = payload( "serverInfo" )
	payload:set( "region", _G.game.initialRegion )
	player:send( payload )
end

shutdown = quit

function update( dt )
	local regions = region.getAll()
	for _, region in ipairs( regions ) do
		region:update( dt )
	end

	network.update( dt )
end

function upload( filename, peer )
	local payload = payload( "upload" )
	payload:set( "filename", filename )
	payload:set( "file", filesystem.read( filename ) )
	peer:send( payload:serialize() )
end
