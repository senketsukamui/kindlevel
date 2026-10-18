-- Verified HTTPS for public GitHub releases; no credentials or background checks.
local Network = {}
Network.__index = Network
local hosts = { ["api.github.com"]=true, ["github.com"]=true,
    ["release-assets.githubusercontent.com"]=true, ["objects.githubusercontent.com"]=true }

function Network.allowed(url)
    local parsed=require("socket.url").parse(url)
    return parsed and parsed.scheme=="https" and hosts[(parsed.host or ""):lower()]
        and not parsed.user and not parsed.password and (not parsed.port or tostring(parsed.port)=="443")
end

function Network.certificateMatches(cert,host)
    if not cert then return false end
    if cert.checkhost then return cert:checkhost(host)==true end
    local extensions=cert:extensions()
    local names=(extensions["2.5.29.17"] or {}).dNSName or {}
    host=host:lower()
    for _,name in ipairs(names) do
        name=name:lower()
        if name==host then return true end
        if name:sub(1,2)=="*." then
            local suffix=name:sub(2)
            local prefix=host:sub(1,#host-#suffix)
            if host:sub(-#suffix)==suffix and prefix~="" and not prefix:find(".",1,true) then return true end
        end
    end
    return false
end

function Network:new(cafile)
    return setmetatable({cafile=cafile},self)
end

function Network.connectionError(address,reason)
    local host=require("socket.url").parse(address).host or "GitHub"
    local detail=tostring(reason or "unknown networking error"):lower()
    if detail:find("certificate",1,true) or detail:find("ssl",1,true) or detail:find("tls",1,true) then
        return "HTTPS verification failed for " .. host .. ". Check the Kindle's date and time and update KOReader if its TLS support is old.",false
    elseif detail:find("timeout",1,true) or detail:find("timed out",1,true) then
        return "Connection timed out while contacting " .. host .. ". Check Wi-Fi or try another network.",true
    elseif detail:find("host not found",1,true) or detail:find("name or service",1,true) or detail:find("resolve",1,true) then
        return "Cannot resolve " .. host .. ". Check Wi-Fi DNS or try another network.",true
    elseif detail:find("refused",1,true) then
        return "Connection refused by " .. host .. ". Check whether this Wi-Fi network blocks GitHub.",true
    elseif detail:find("exceeds",1,true) then
        return "The update response exceeds its size limit.",false
    end
    return "Cannot contact " .. host .. ". Check Wi-Fi and try again. (" .. detail:sub(1,160) .. ")",true
end

function Network:fetch(address,destination,limit)
    for attempt=1,2 do
        local result,err,bytes,final,retry=self:fetchOnce(address,destination,limit)
        if result then return result,err,bytes,final end
        if destination then os.remove(destination) end
        if not retry or attempt==2 then return nil,err end
    end
end

function Network:fetchOnce(address,destination,limit)
    local http=require("socket.http")
    local https=require("ssl.https")
    local socketutil=require("socketutil")
    local urls=require("socket.url")
    local current=address
    if http.PROXY then return nil,"HTTPS proxies are not supported by the updater." end
    for redirect=0,5 do
        if not Network.allowed(current) then return nil,"The update URL is not an approved HTTPS address." end
        local chunks,bytes,file={},0,nil
        if destination then
            file=io.open(destination,"wb")
            if not file then return nil,"Cannot create the update download. Check available storage." end
        end
        local make_tls=https.tcp{protocol="any",verify="peer",cafile=self.cafile,
            options={"all","no_sslv2","no_sslv3","no_tlsv1","no_tlsv1_1"}}
        local function create()
            local connection=make_tls()
            local connect=connection.connect
            function connection:connect(host,port)
                local result,err=connect(self,host,port)
                if not result then return nil,err end
                if not Network.certificateMatches(self.sock:getpeercertificate(),host) then
                    self.sock:close(); error("TLS certificate does not match the update server")
                end
                return result
            end
            return connection
        end
        local started=os.time()
        local function sink(chunk,err)
            if err then return nil,err end
            if os.time()-started>90 then return nil,"Update download timed out" end
            if chunk then
                bytes=bytes+#chunk
                if bytes>limit then return nil,"Update download exceeds its size limit" end
                if file then
                    local ok,write_err=file:write(chunk)
                    if not ok then return nil,write_err end
                else chunks[#chunks+1]=chunk end
            end
            return 1
        end
        socketutil:set_timeout(10,90)
        local ok,success,code,headers=pcall(http.request,{url=current,create=create,redirect=false,
            headers={Accept=current:find("api.github.com",1,true) and "application/vnd.github+json" or "*/*",["User-Agent"]="Kindlevel updater"},sink=sink})
        socketutil:reset_timeout()
        if file then file:close() end
        if not ok or not success then
            local message,retry=Network.connectionError(current,ok and code or success)
            return nil,message,nil,nil,retry
        end
        if code==200 then return destination and true or table.concat(chunks),nil,bytes,current end
        if code==301 or code==302 or code==303 or code==307 or code==308 then
            if not headers or not headers.location or redirect==5 then return nil,"Too many update redirects." end
            current=urls.absolute(current,headers.location)
        else
            if code==403 or code==429 then return nil,"GitHub refused the request or its request limit was reached. Try again later." end
            if code==404 then return nil,"No update release was found on GitHub." end
            return nil,"GitHub returned HTTP " .. tostring(code) .. ". Try again later.",nil,nil,tonumber(code) and tonumber(code)>=500
        end
    end
end

return Network
