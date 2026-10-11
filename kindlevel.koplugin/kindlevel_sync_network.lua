-- Same-server JSON requests. HTTPS is verified; redirects never receive tokens.
local Network={}
Network.__index=Network

local function localHost(host)
    host=host:lower()
    local a,b,c,d=host:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
    if a then
        a,b,c,d=tonumber(a),tonumber(b),tonumber(c),tonumber(d)
        if a>255 or b>255 or c>255 or d>255 then return false end
        if table.concat({a,b,c,d},".")~=host then return false end
        return a==10 or a==127 or a==192 and b==168 or a==172 and b>=16 and b<=31
    end
    return host=="localhost" or host:sub(-6)==".local"
end

function Network.address(value,allow_http)
    if type(value)~="string" or #value>512 or value:find("[%c%s]") then return nil,"Enter a server address such as https://books.example.com." end
    value=value:gsub("/+$","")
    local url=require("socket.url").parse(value)
    if not url or not url.host or url.user or url.password or url.query or url.fragment or url.path and url.path~="" then
        return nil,"Use the server's address without a path, username or password."
    end
    if url.port and (not tostring(url.port):match("^%d+$") or tonumber(url.port)<1 or tonumber(url.port)>65535) then return nil,"The server port is invalid." end
    if url.scheme~="https" and not (url.scheme=="http" and allow_http and localHost(url.host)) then
        return nil,"Use HTTPS, or explicitly allow HTTP with a trusted local network address."
    end
    return value
end

function Network:new(options)
    return setmetatable({cafile=options.cafile,allow_http=options.allow_http==true},self)
end

function Network:request(server,path,body,token)
    local address,err=Network.address(server,self.allow_http)
    if not address then return nil,err end
    local http=require("socket.http")
    local https=require("ssl.https")
    local ltn12=require("ltn12")
    local socketutil=require("socketutil")
    if http.PROXY then return nil,"HTTP proxies are not supported by Kindle sync." end
    local headers={Accept="application/json",["Content-Type"]="application/json",["Content-Length"]=tostring(#body),["User-Agent"]="Kindlevel/" .. require("kindlevel_version")}
    if token then headers.Authorization="Bearer " .. token end
    local create
    if address:sub(1,8)=="https://" then
        local tls=https.tcp{protocol="any",verify="peer",cafile=self.cafile,options={"all","no_sslv2","no_sslv3","no_tlsv1","no_tlsv1_1"}}
        create=function()
            local connection=tls()
            local connect=connection.connect
            function connection:connect(host,port)
                local result=connect(self,host,port)
                if not require("kindlevel_update_network").certificateMatches(self.sock:getpeercertificate(),host) then
                    self.sock:close();error("Sync certificate does not match the server")
                end
                return result
            end
            return connection
        end
    end
    local chunks,bytes={},0
    local started=os.time()
    local function sink(chunk,failure)
        if failure then return nil,failure end
        if os.time()-started>90 then return nil,"Sync timed out" end
        if chunk then bytes=bytes+#chunk;if bytes>32768 then return nil,"Server response too large" end;chunks[#chunks+1]=chunk end
        return 1
    end
    socketutil:set_timeout(10,90)
    local ok,success,code=pcall(http.request,{url=address .. path,method="POST",create=create,redirect=false,headers=headers,source=ltn12.source.string(body),sink=sink})
    socketutil:reset_timeout()
    if not ok or not success then return nil,"Cannot reach the server. Check Wi-Fi, the address, and the Kindle's date and time." end
    if tonumber(code)>=300 and tonumber(code)<400 then return nil,"The server redirected the request. Enter its final HTTPS address and try again." end
    local parsed_ok,result=pcall(require("json").decode,table.concat(chunks))
    if tonumber(code)~=200 then
        return nil,parsed_ok and type(result)=="table" and type(result.error)=="string" and result.error or "The server returned HTTP " .. tostring(code) .. "."
    end
    if not parsed_ok or type(result)~="table" then return nil,"The server did not return a Kindlevel response. Check its address." end
    return result
end

return Network
