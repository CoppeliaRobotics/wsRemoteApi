local sim = require 'sim'
local simWS
local json
local cbor

if _removeLazyLoaders then _removeLazyLoaders() end

wsRemoteApi = {}

function wsRemoteApi.verbose()
    return sim.getNamedInt32Param('wsRemoteApi.verbose') or 0
end

function wsRemoteApi.require(name)
    _G[name] = require(name)
end

function wsRemoteApi.info(obj)
    if type(obj) == 'string' then obj = wsRemoteApi.getField(obj) end
    if type(obj) ~= 'table' then return obj end
    local ret = {}
    for k, v in pairs(obj) do
        if type(v) == 'table' then
            ret[k] = wsRemoteApi.info(v)
        elseif type(v) == 'function' then
            ret[k] = {func = {}}
        elseif type(v) ~= 'function' then
            ret[k] = {const = v}
        end
    end
    return ret
end

function wsRemoteApi.getField(f)
    local v = _G
    for w in string.gmatch(f, '[%w_]+') do
        v = v[w]
        if not v then return nil end
    end
    return v
end

function wsRemoteApi.handleRequest(req)
    if wsRemoteApi.verbose() > 1 then print('request received:', req) end
    local resp = {}
    resp['id'] = req['id']
    if req['func'] ~= nil and req['func'] ~= '' then
        local func = wsRemoteApi.getField(req['func'])
        local args = req['args'] or {}
        if not func then
            resp['error'] = 'No such function: ' .. req['func']
        else
            local status, retvals = pcall(
                                        function()
                    local ret = {func(unpack(args))}
                    return ret
                end
                                    )
            resp[status and 'ret' or 'error'] = retvals
        end
    elseif req['eval'] ~= nil and req['eval'] ~= '' then
        local status, retvals = pcall(
                                    function()
                local ret = {loadstring('return ' .. req['eval'])()}
                return ret
            end
                                )
        resp[status and 'ret' or 'error'] = retvals
    end
    resp['success'] = resp['error'] == nil
    if wsRemoteApi.verbose() > 1 then print('returning response:', resp) end
    return resp
end

function onWSMessage(server, connection, message)
    local rawReq = message

    -- if first byte is '{', it *might* be a JSON payload
    if rawReq:byte(1) == 123 then
        local req, ln, err = json.decode(tostring(rawReq))
        if req ~= nil then
            local resp = wsRemoteApi.handleRequest(req)
            resp = json.encode(resp)
            simWS.send(server, connection, resp, simWS.opcode.text)
            return
        end
    end

    -- if we are here, it should be a CBOR payload
    local status, req = pcall(cbor.decode, tostring(rawReq))
    if status then
        local resp = wsRemoteApi.handleRequest(req)
        resp = cbor.encode(resp)
        -- resp=sim.packTable(resp,1)
        simWS.send(server, connection, resp, simWS.opcode.binary)
        return
    end

    sim.addLog(sim.verbosity_errors, 'cannot decode message: no suitable decoder')
    return ''
end

function wsRemoteApi.publishStepCount()
    -- if wsRemoteApi.verbose()>1 then
    --    print('publishing simulationTimeStepCount='..simulationTimeStepCount)
    -- end
end

function sysCall_info()
    return {
        menu = 'Connectivity\nWebSocket remote API server',
    }
end

function sysCall_init()
    simWS = require 'simWS'
    local defaultPort = 23050 + sim.getInt32Param(sim.intparam_processid)
    local port = sim.getNamedInt32Param('wsRemoteApi.port') or defaultPort
    sim.setNamedInt32Param('wsRemoteApi.port', port)
--    if wsRemoteApi.verbose() > 0 then
        sim.addLog(
            sim.verbosity_scriptinfos,
            string.format('WebSocket Remote API server starting (port=%d)...', port)
        )
--    end
    json = require 'dkjson'
    -- cbor=require 'cbor' -- encodes strings as buffers, always. DO NOT USE!!
    cbor = require 'org.conman.cbor'
    wsServer = simWS.start(port)
    simWS.setMessageHandler(wsServer, 'onWSMessage')
    if wsRemoteApi.verbose() > 0 then
        sim.addLog(sim.verbosity_scriptinfos, 'WebSocket Remote API server started')
    end
    stepping = false
end

function sysCall_cleanup()
    if not simWS then return end
    if wsServer then simWS.stop(wsServer) end
    if wsRemoteApi.verbose() > 0 then
        sim.addLog(sim.verbosity_scriptinfos, 'WebSocket Remote API server stopped')
    end
end

function sysCall_addOnScriptSuspend()
    return {cmd = 'cleanup'}
end

function sysCall_addOnScriptSuspended()
    return {cmd = 'cleanup'}
end

function sysCall_nonSimulation()
end

function sysCall_beforeMainScript()
    local outData
    if stepping then
        outData = {doNotRunMainScript = not go}
        go = nil
    end
    return outData
end

function sysCall_beforeSimulation()
    simulationTimeStepCount = 0
    wsRemoteApi.publishStepCount()
end

function sysCall_actuation()
    simulationTimeStepCount = simulationTimeStepCount + 1
    wsRemoteApi.publishStepCount()
end

function sysCall_afterSimulation()
    stepping = false -- auto disable sync. mode
end

function setStepping(enable)
    stepping = enable
    go = nil
end

function step()
    go = true
end

require('addOns.autoStart').setup{ns = 'wsRemoteApi', default = true}
